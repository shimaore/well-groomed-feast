    dgram = require 'dgram'
    Promise = require 'bluebird'
    seem = require 'seem'
    dns = Promise.promisifyAll require 'dns'
    pkg = require '../package.json'
    @name = "#{pkg.name}:mwi_notifier"
    debug = (require 'debug') @name
    User = require '../src/User'

    assert = require 'assert'

Handle SUBSCRIBE messages
=========================

    socket = dgram.createSocket 'udp4'

    socket.on 'error', (error) ->
      debug "Socket error: #{error}"

    @server_pre = (cfg) ->

Note: I believe these are currently not forwarded by ccnq4-opensips.

      socket.on 'message', (msg,rinfo) ->
        content = msg.toString 'ascii'

Try to recover the number and the endpoint from the message

        return unless r = content.match /^SUBSCRIBE sip:(\S+)@.*\nX-CCNQ3-Endpoint: (\S+)\n/

        number = r[1]
        endpoint = r[2]

Recover the number-domain from the endpoint.

        {number_domain} = yield cfg.prov.get "endpoint:#{endpoint}"
        user_id = "#{number}@#{number_domain}"

Recover the local-number's user-database.

        {user_database} = yield cfg.prov.get "number:#{user_id}"
        db_uri = cfg.userdb_base_uri + '/' + user_database

Create a User object and use it to send the notification.

        send_notification_to new User {cfg}, user_id, user_database, db_uri

Start socket
------------

      socket.bind cfg.voicemail?.notifier_port ? 7124

Unsollicited NOTIFY
===================

    @include = ->
      @cfg.notifiers ?= {}
      return if @cfg.notifiers.mwi?

By default we issue "Unsollicited NOTIFY" messages.

      @cfg.notifiers.mwi ?= send_notification_to

      debug 'Configured.'

Notifier Callback: Send notification to a user
==============================================

    send_notification_to = seem (user,id,flag) ->
      debug 'send_notification_to', {user}
      cfg = user.ctx.cfg

Collect the number of messages from the user's database.

      {total_rows} = yield user.db.query 'voicemail/new_messages'

When a new message is posted we might come too soon (for CouchDB) and get an invalid `total_rows` value.

      total_rows = 1 if flag is 'create' and total_rows is 0

Collect the endpoint/via fields from the local number.

      number_doc = yield cfg.prov.get "number:#{user.id}"
      return if number_doc.disabled

      via = number_doc.endpoint_via

Use the endpoint name and via to route the packet.

      endpoint = number_doc.endpoint

Registered endpoint

      if m = endpoint.match /^([^@]+)@([^@]+)$/
        to = endpoint
        if via?
          uri = [m[1],via].join '@'
        else
          uri = endpoint
        debug 'Notifying endpoint', {endpoint,uri,to}
        notify uri, to, total_rows

Static endpoint

      else
        if via?
          to = [user.id,endpoint].join '@'
          uri = [user.id,via].join '@'
          debug 'Notifying endpoint', {endpoint,uri,to}
          notify uri, to, total_rows
        else
          debug 'No `via` for static endpoint, skipping.'

      return

Notify a specific URI
=====================

We route based on the URI domain, as per RFC.

    notify = seem (uri,to,total_rows) ->
      debug 'notify', {uri,to,total_rows}

URI = username@host:port

      if m = uri.match /^([^@]+)@(^[@:]+):(\d+)$/
        name = m[2]
        port = m[3]
        debug 'Address', {name,port}
        send_sip_notification uri, to, total_rows, port, name
        return

URI = username@domain

      if m = uri.match /^([^@]+)@([^@:]+)$/
        domain = m[2]

        addresses = yield dns.resolveSrvAsync '_sip._udp.' + domain
        debug 'Addresses', addresses
        for address in addresses
          do (address) ->
            send_sip_notification uri, to, total_rows, address.port, address.name

Also send to username@domain:5060
FIXME: this probably should only happen if `addresses` is empty?

        try send_sip_notification uri, to, total_rows, 5060, domain
        return

      debug 'Invalid URI', {uri}
      return

Send notification packet to an URI at a given address and port
==============================================================

    send_sip_notification = (uri,to,total_rows,target_port,target_name) ->
      debug 'Send SIP notification', {uri,target_port,target_name}

      body = new Buffer """
        Message-Waiting: #{if total_rows > 0 then 'yes' else 'no'}
      """

      # FIXME no tag, etc.
      headers = new Buffer """
        NOTIFY sip:#{uri} SIP/2.0
        Via: SIP/2.0/UDP #{target_name}:#{target_port};branch=0
        Max-Forwards: 2
        To: <sip:#{to}>
        From: <sip:#{to}>
        Call-ID: #{pkg.name}-#{Math.random()}
        CSeq: 1 NOTIFY
        Event: message-summary
        Subscription-State: active
        Content-Type: application/simple-message-summary
        Content-Length: #{body.length}
        \n
      """.replace /\n/g, "\r\n"

      message = new Buffer headers.length + body.length
      headers.copy message
      body.copy message, headers.length

      socket.send message, 0, message.length, target_port, target_name
      debug 'Sent SIP notification'
      return
