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

    socket.on 'listening', ->
      address = socket.address()
      debug "Listening for SUBSCRIBE messages on #{address.address}:#{address.port}"

    test_msg = '''
      SUBSCRIBE sip:test.phone.kwaoo.net SIP/2.0
      X-CCNQ3-Endpoint: 0972222713@a.phone.kwaoo.net
      Via: SIP/2.0/UDP 192.168.1.106:5063;branch=z9hG4bK-5e721c6;rport
      From: <sip:0972222713@test.phone.kwaoo.net>;tag=ed1530ada8e777c4
      To: <sip:test.phone.kwaoo.net>
      Call-ID: 15591da1-15214f60@192.168.1.106
      CSeq: 55159 SUBSCRIBE
      Max-Forwards: 69
      Proxy-Authorization: Digest username="0972222713",realm="test.phone.kwaoo.net",nonce="56a632ef0000001adeb0832ae67fe8747a68b3061dfb4349",uri="sip:test.phone.kwaoo.net",algorithm=MD5,response="8fb39ce0525f332b42e34d87ac7a6741"
      Contact: <sip:0972222713@192.168.1.106:5063>
      Expires: 2147483647
      Event: message-summary
      User-Agent: Linksys/SPA962-6.1.5(a)
      Content-Length: 0

    '''

    msg_matcher =
          ///
          ^
          SUBSCRIBE \s+ sip:
          [\S\s]*
          \n
          X-CCNQ3-Endpoint: \s* (\S+)
          [\r\n]
          [\S\s]*
          \n
          From: \s* <sip:(\d+)@
          ///

    assert test_msg.match msg_matcher

    @server_pre = ->

Note: I believe these are currently not forwarded by ccnq4-opensips.

      socket.on 'message', seem (msg,rinfo) =>
        debug "Received #{msg.length} bytes message from #{rinfo.address}:#{rinfo.port}"
        content = msg.toString 'ascii'
        debug 'Received message', content

Try to recover the number and the endpoint from the message
FIXME: Replace with proper SIP parsing.

        return unless r = content.match msg_matcher
        number = r[2]
        endpoint = r[1]

        debug 'SUBSCRIBE', {number, endpoint}

Recover the number-domain from the endpoint.

        {number_domain} = yield @cfg.prov.get "endpoint:#{endpoint}"
        user_id = "#{number}@#{number_domain}"

        debug 'SUBSCRIBE', {number_domain,user_id}

Recover the local-number's user-database.

        {user_database} = yield @cfg.prov.get "number:#{user_id}"
        db_uri = @cfg.userdb_base_uri + '/' + user_database

        debug 'SUBSCRIBE', {user_database,db_uri}

Create a User object and use it to send the notification.

        send_notification_to new User this, user_id, user_database, db_uri

Start socket
------------

      socket.bind @cfg.voicemail?.notifier_port ? 7124


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
