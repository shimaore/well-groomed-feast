    dgram = require 'dgram'
    pkg = require '../package.json'
    @name = "#{pkg.name}:middleware:mwi_notifier"
    {debug,foot} = (require 'tangible') @name
    trace = ->
    User = require '../src/User'
    CouchDB = require 'most-couchdb'

    send_notification_to = null

    @include = ->
      @cfg.notifiers ?= {}
      @cfg.notifiers.mwi ?= send_notification_to
      null

    get_prov = require 'five-toes/get-prov'
    message_summary = require 'five-toes/message-summary'
    ccnq4_resolve = require 'five-toes/ccnq4-resolve'
    ccnq4_receiver = require 'five-toes/ccnq4-receiver'
    SIPSender = require 'five-toes/sip-sender'

    socket = dgram.createSocket 'udp4'
    sender = new SIPSender socket

    @end = ->
      socket.close()

    @server_pre = (ctx) ->
      {cfg} = ctx
      debug 'server_pre'

      prov = new CouchDB cfg.provisioning
      receive = ccnq4_receiver cfg
      resolve = ccnq4_resolve cfg

      receive socket, ({user_id}) ->

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

        content = message_summary new_messages, saved_messages

Collect the endpoint/via fields from the local number.

        dest = await resolve user.id

* doc.local_number.endpoint_via (domain name string) If present, domain name used to route voicemail notifications via the SUBSCRIBE/PUBLISH mechanism. It is optional for dynamic endpoints (`<username>@<endpoint-domain>`) and required for static endpoints. Default: the domain of doc.local_number.endpoint (for dynamic endpoints), none for static endpoints.
* doc.local_number.endpoint (endpoint name string) If `<username>@<endpoint-domain>`, used for routing voicemail notifications va the SUBSCRIBE/PUBLISH mechanism, unless doc.local_number.endpoint_via is specified. If `<endpoint-domain>` (for static endpoints), domain name used as destination for voicemail notifications, while routing is done using the doc.local_number.endpoint_via domain name.

        await sender.publish dest, content

        trace 'send_notification_to: done', user.id
        return

      debug 'Configured.'
      return
