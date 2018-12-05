    dgram = require 'dgram'
    pkg = require '../package.json'
    @name = "#{pkg.name}:middleware:mwi_notifier"
    {debug,foot} = (require 'tangible') @name
    trace = ->
    User = require '../src/User'
    Parser = require 'jssip/lib/Parser'
    CouchDB = require 'most-couchdb'

    send_notification_to = null

    @include = ->
      @cfg.notifiers ?= {}
      @cfg.notifiers.mwi ?= send_notification_to
      null

    get_prov = require '../lib/get_prov'
    notify = require '../lib/notify'

    socket = dgram.createSocket 'udp4'

    socket.on 'error', (error) ->
      debug.dev "Socket error: #{error}"

    socket.once 'listening', ->
      address = socket.address()
      debug "Listening for SUBSCRIBE messages on #{address.address}:#{address.port}"

    @end = ->
      socket.close()

    @server_pre = (ctx) ->
      {cfg} = ctx
      debug 'server_pre'

      prov = new CouchDB cfg.provisioning

      socket.on 'message', (msg,rinfo) ->
        debug "Received #{msg.length} bytes message from #{rinfo.address}:#{rinfo.port}"

        content = msg.toString 'ascii'
        trace 'Received message', content

        ua = {}

The parser returns an IncomingRequest for a SUBSCRIBE message.

        request = Parser.parseMessage content, ua
        return unless request? and request.method is 'SUBSCRIBE' and request.event?.event is 'message-summary'

Try to recover the number and the endpoint from the message.

        number = request.ruri?.user ? request.from?.uri?.user
        endpoint = request.headers['X-En']?[0]?.raw

        trace 'SUBSCRIBE', {number, endpoint}

        return unless number? and endpoint?

Recover the number-domain from the endpoint.

        {number_domain} = await get_prov prov, "endpoint:#{endpoint}"

        user_id = "#{number}@#{number_domain}"

        trace 'SUBSCRIBE', {number_domain,user_id}

        return unless number_domain?

Recover the local-number's user-database.

        {user_database} = await get_prov prov, "number:#{user_id}"

Ready to send a notification

        db_uri = cfg.userdb_base_uri + '/' + user_database

        trace 'SUBSCRIBE', {user_database,db_uri}

        return unless user_database?

        request = null

Create a User object and use it to send the notification.

        user = new User ctx, user_id, user_database, db_uri
        try
          await send_notification_to user
        catch error
          debug "SUBSCRIBE send_notification_to: #{error.stack ? error}", user_id
        finally
          await user.close_db()
          user = null

        debug "SUBSCRIBE done"
        return


Start socket
------------

* cfg.voicemail.notifier_port (integer) Port number for the (UDP) forwarding of SUBSCRIBE messages for voicemail notifications.

      socket.bind cfg.voicemail?.notifier_port ? 7124

Notifier Callback: Send notification to a user
==============================================

      send_notification_to = (user) ->
        trace 'send_notification_to', user.id

Collect the number of messages from the user's database.

        rows = await user.get_new_messages()
        new_messages = rows.length
        rows = await user.get_saved_messages()
        saved_messages = rows.length
        trace 'send_notification_to', {new_messages,saved_messages}

Collect the endpoint/via fields from the local number.

        number_doc = await get_prov prov, "number:#{user.id}"
        return if number_doc.disabled

* doc.local_number.endpoint_via (domain name string) If present, domain name used to route voicemail notifications via the SUBSCRIBE/PUBLISH mechanism. It is optional for dynamic endpoints (`<username>@<endpoint-domain>`) and required for static endpoints. Default: the domain of doc.local_number.endpoint (for dynamic endpoints), none for static endpoints.
* doc.local_number.endpoint (endpoint name string) If `<username>@<endpoint-domain>`, used for routing voicemail notifications va the SUBSCRIBE/PUBLISH mechanism, unless doc.local_number.endpoint_via is specified. If `<endpoint-domain>` (for static endpoints), domain name used as destination for voicemail notifications, while routing is done using the doc.local_number.endpoint_via domain name.

        via = number_doc.endpoint_via

Use the endpoint name and via to route the packet.

        endpoint = number_doc.endpoint

        trace 'send_notification_to', {via,endpoint}

        return unless endpoint?

Registered endpoint

        if m = endpoint.match /^([^@]+)@([^@]+)$/
          to = endpoint
          if via?
            uri = [m[1],via].join '@'
          else
            uri = endpoint
          debug 'Notifying endpoint', {endpoint,uri,to}
          await notify socket, uri, to, new_messages, saved_messages

Static endpoint

        else
          if via?
            to = [user.id,endpoint].join '@'
            uri = [user.id,via].join '@'
            debug 'Notifying endpoint', {endpoint,uri,to}
            await notify socket, uri, to, new_messages, saved_messages
          else
            debug 'No `via` for static endpoint, skipping.'

        debug 'send_notification_to done', user.id
        return

      debug 'Configured.'
      return
