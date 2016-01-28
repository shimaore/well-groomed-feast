    dgram = require 'dgram'
    Promise = require 'bluebird'
    seem = require 'seem'
    dns = Promise.promisifyAll require 'dns'
    pkg = require '../package.json'
    @name = "#{pkg.name}:mwi_notifier"
    debug = (require 'debug') @name
    trace = (require 'debug') "#{@name}:trace"
    User = require '../src/User'
    Parser = require 'jssip/lib/Parser'

    assert = require 'assert'

Handle SUBSCRIBE messages
=========================

    socket = dgram.createSocket 'udp4'

    socket.on 'error', (error) ->
      debug "Socket error: #{error}"

    socket.on 'listening', ->
      address = socket.address()
      debug "Listening for SUBSCRIBE messages on #{address.address}:#{address.port}"

This format is probably incorrect per section 3.1.2 of RFC3265 (the RURI or Event `id` field should uniquely identify the resource).

    _test = ->
      test_msg1 = '''
        SUBSCRIBE sip:test.phone.kwaoo.net SIP/2.0
        X-CCNQ3-Endpoint: 0972222713@a.phone.kwaoo.net
        Via: SIP/2.0/UDP 192.168.1.106:5063;branch=z9hG4bK-5e721c6;rport
        From: <sip:0972222713@test.phone.kwaoo.net>;tag=ed1530ada8e777c4
        To: <sip:test.phone.kwaoo.net>
        Call-ID: 15591da1-15214f60@192.168.1.106
        CSeq: 55159 SUBSCRIBE
        Max-Forwards: 69
        Contact: <sip:0972222713@192.168.1.106:5063>
        Expires: 2147483647
        Event: message-summary
        User-Agent: Linksys/SPA962-6.1.5(a)
        Content-Length: 0
        \n
      '''

      test_msg2 = '''
        SUBSCRIBE sip:0972369812@a.phone.kwaoo.net SIP/2.0
        X-CCNQ3-Endpoint: 0972369812@a.phone.kwaoo.net
        Via: SIP/2.0/UDP 89.36.202.179:5060;branch=z9hG4bKddcd4dd080f01129f7749721fb029c7b;rport
        From: "0478182907" <sip:0972369812@a.phone.kwaoo.net>;tag=494263519
        To: "0478182907" <sip:0972369812@a.phone.kwaoo.net>
        Call-ID: 2516407383@192_168_1_2
        CSeq: 10319968 SUBSCRIBE
        Contact: <sip:0972369812@89.36.202.179:5060>
        Max-Forwards: 69
        User-Agent: C610 IP/42.075.00.000.000
        Event: message-summary
        Expires: 3600
        Allow: NOTIFY
        Accept: application/simple-message-summary
        Content-Length: 0
        \n
      '''

      assert.strictEqual (Parser.parseMessage test_msg1.replace(/\n/g,'\r\n'), null).method, 'SUBSCRIBE'
      assert.strictEqual (Parser.parseMessage test_msg2.replace(/\n/g,'\r\n'), null).method, 'SUBSCRIBE'
      assert.strictEqual typeof (Parser.parseMessage test_msg1.replace(/\n/g,'\r\n'), null).ruri.user, 'undefined'
      assert.strictEqual (Parser.parseMessage test_msg2.replace(/\n/g,'\r\n'), null).ruri.user, '0972369812'
      assert.strictEqual (Parser.parseMessage test_msg2.replace(/\n/g,'\r\n'), null).event.event, 'message-summary'

      test_msg1 = null
      test_msg2 = null


    do _test

    @server_pre = ->

      socket.on 'message', seem (msg,rinfo) =>
        debug "Received #{msg.length} bytes message from #{rinfo.address}:#{rinfo.port}"
        content = msg.toString 'ascii'
        trace 'Received message', content

        ua =
          send: (msg) ->
            message = msg.toString()

Send our response (200 OK) back to the IP and port the message come from.

            socket.send message, 0, message.length, rinfo.port, rinfo.address

        message = Parser.parseMessage content, null
        return unless message? and message.method is 'SUBSCRIBE' and message.event?.event is 'message-summary'

Try to recover the number and the endpoint from the message.

        number = message.ruri?.user ? message.from?.uri?.user
        endpoint = message.headers['X-Ccnq3-Endpoint']?[0]?.raw

        trace 'SUBSCRIBE', {number, endpoint}

Recover the number-domain from the endpoint.

        {number_domain} = yield @cfg.prov.get "endpoint:#{endpoint}"
        user_id = "#{number}@#{number_domain}"

        trace 'SUBSCRIBE', {number_domain,user_id}

Recover the local-number's user-database.

        {user_database} = doc = yield @cfg.prov.get "number:#{user_id}"

Record the Event header, dialog, etc. in a LRU-cache so that they may be used in NOTIFY messages.

        # FIXME

Ready to send a notification

        db_uri = @cfg.userdb_base_uri + '/' + user_database

        trace 'SUBSCRIBE', {user_database,db_uri}

We set the Expires header so that the client is forced to re-SUBSCRIBE regularly.
FIXME: RFC3265 section 3.1.1 requires that our Expires be <= to the one requested in the SUBSCRIBE message.

        message.reply 200, 'OK', Expires: 600

Create a User object and use it to send the notification.

        send_notification_to new User this, user_id, user_database, db_uri

Start socket
------------

* cfg.voicemail.notifier_port (integer) Port number for the (UDP) forwarding of SUBSCRIBE messages for voicemail notifications.

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


    resolve = seem (uri) ->

      result = []

URI = username@host:port

      if m = uri.match /^([^@]+)@(^[@:]+):(\d+)$/
        name = m[2]
        port = m[3]
        trace 'resolve', {name,port}
        results.push {port,name}

URI = username@domain

      if m = uri.match /^([^@]+)@([^@:]+)$/
        domain = m[2]

        addresses = yield dns.resolveSrvAsync '_sip._udp.' + domain
        trace 'Addresses', addresses
        for address in addresses
          do (address) ->
            results.push address

      result

Notify a specific URI
=====================

We route based on the URI domain, as per RFC.

    notify = seem (uri,to,total_rows) ->
      debug 'notify', {uri,to,total_rows}

      addresses = yield resolve uri

      for address in addresses
        do (address) ->
          send_sip_notification uri, to, total_rows, address.port, address.name

      return

Send notification packet to an URI at a given address and port
==============================================================

    send_sip_notification = (uri,to,total_rows,target_port,target_name) ->
      debug 'Send SIP notification', {uri,target_port,target_name}

      body = new Buffer """
        Message-Waiting: #{if total_rows > 0 then 'yes' else 'no'}
      """

RFC365, section 3.3.4:

> NOTIFY requests are matched to such SUBSCRIBE requests if they
> contain the same "Call-ID", a "To" header "tag" parameter which
> matches the "From" header "tag" parameter of the SUBSCRIBE, and the
> same "Event" header field.  Rules for comparisons of the "Event"
> headers are described in section 7.2.1.  If a matching NOTIFY request
> contains a "Subscription-State" of "active" or "pending", it creates
> a new subscription and a new dialog (unless they have already been
> created by a matching response, as described above).

      headers = new Buffer """
        NOTIFY sip:#{uri} SIP/2.0
        Via: SIP/2.0/UDP #{target_name}:#{target_port};branch=0
        Max-Forwards: 2
        To: <sip:#{to}>
        From: <sip:#{to}>;tag=#{Math.random()}
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
