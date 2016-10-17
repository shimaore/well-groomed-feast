    dgram = require 'dgram'
    seem = require 'seem'
    pkg = require '../package.json'
    @name = "#{pkg.name}:middleware:mwi_notifier"
    debug = (require 'debug') @name
    trace = (require 'debug') "#{@name}:trace"
    User = require '../src/User'
    Parser = require 'jssip/lib/Parser'

    send_notification_to = null

    @include = ->
      @cfg.notifiers ?= {}
      @cfg.notifiers.mwi ?= send_notification_to
      null

    get_prov = require '../lib/get_prov'
    notify = require '../lib/notify'

    @server_pre = (ctx) ->
      cfg = ctx.cfg
      debug "server_pre, ctx = ", ctx

      socket = dgram.createSocket 'udp4'

      socket.on 'error', (error) ->
        debug "Socket error: #{error}"

      socket.on 'listening', ->
        address = socket.address()
        debug "Listening for SUBSCRIBE messages on #{address.address}:#{address.port}"

      socket.on 'message', ->
        args = arguments
        on_message
          .apply ctx, args
          .catch (error) ->
            debug "on_message: #{error}\n#{error.stack}"

      on_message = seem (msg,rinfo) ->
        debug "Received #{msg.length} bytes message from #{rinfo.address}:#{rinfo.port}"

        content = msg.toString 'ascii'
        trace 'Received message', content

        ua = {}

The parser returns an IncomingRequest for a SUBSCRIBE message.

        request = Parser.parseMessage content, ua
        return unless request? and request.method is 'SUBSCRIBE' and request.event?.event is 'message-summary'

Try to recover the number and the endpoint from the message.

        number = request.ruri?.user ? request.from?.uri?.user
        endpoint = request.headers['X-Ccnq-Endpoint']?[0]?.raw

        trace 'SUBSCRIBE', {number, endpoint}

        return unless number? and endpoint?

Recover the number-domain from the endpoint.

        {number_domain} = yield get_prov cfg.prov, "endpoint:#{endpoint}"

        user_id = "#{number}@#{number_domain}"

        trace 'SUBSCRIBE', {number_domain,user_id}

        return unless number_domain?

Recover the local-number's user-database.

        {user_database} = yield get_prov cfg.prov, "number:#{user_id}"

Ready to send a notification

        db_uri = cfg.userdb_base_uri + '/' + user_database

        trace 'SUBSCRIBE', {user_database,db_uri}

        return unless user_database?

        request = null

Create a User object and use it to send the notification.

        user = new User ctx, user_id, user_database, db_uri
        try
          yield send_notification_to user
        catch error
          debug "SUBSCRIBE send_notification_to: #{error}\n#{error.stack}", user_id
        finally
          yield user.close_db()
          user = null

        debug "SUBSCRIBE done"
        return


Start socket
------------

* cfg.voicemail.notifier_port (integer) Port number for the (UDP) forwarding of SUBSCRIBE messages for voicemail notifications.

      socket.bind cfg.voicemail?.notifier_port ? 7124

Notifier Callback: Send notification to a user
==============================================

      send_notification_to = seem (user) ->
        trace 'send_notification_to', user.id

Collect the number of messages from the user's database.

        {total_rows} = yield user.db.query 'voicemail/new_messages'
        new_messages = total_rows
        {total_rows} = yield user.db.query 'voicemail/saved_messages'
        saved_messages = total_rows
        trace 'send_notification_to', {new_messages,saved_messages}

Collect the endpoint/via fields from the local number.

        number_doc = yield get_prov cfg.prov, "number:#{user.id}"
        return if number_doc.disabled

        via = number_doc.endpoint_via

Use the endpoint name and via to route the packet.

        endpoint = number_doc.endpoint

        trace 'send_notification_to', {via,endpoint}

Registered endpoint

        if m = endpoint.match /^([^@]+)@([^@]+)$/
          to = endpoint
          if via?
            uri = [m[1],via].join '@'
          else
            uri = endpoint
          debug 'Notifying endpoint', {endpoint,uri,to}
          yield notify socket, uri, to, new_messages, saved_messages

Static endpoint

        else
          if via?
            to = [user.id,endpoint].join '@'
            uri = [user.id,via].join '@'
            debug 'Notifying endpoint', {endpoint,uri,to}
            yield notify socket, uri, to, new_messages, saved_messages
          else
            debug 'No `via` for static endpoint, skipping.'

        debug 'send_notification_to done', user.id
        return
