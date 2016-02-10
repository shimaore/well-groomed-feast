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
    {NonInviteServerTransaction} = require 'jssip/lib/Transactions'
    LRU = require 'lru-cache'

Unsollicited NOTIFY
===================

By default we issue "Unsollicited NOTIFY" messages.

    send_notification_to = null

    @include = ->
      @cfg.notifiers ?= {}
      return if @cfg.notifiers.mwi?

      @cfg.notifiers.mwi ?= send_notification_to

URI DNS resolution and cache
============================

    dns_cache = LRU
      max: 200
      maxAge: 10 * 60 * 1000

    resolve = seem (uri) ->

      result = dns_cache.get uri
      return result if result?

      result = []

URI = username@host:port

      if m = uri.match /^([^@]+)@(^[@:]+):(\d+)$/
        name = m[2]
        port = m[3]
        trace 'resolve', {name,port}
        result.push {port,name}

URI = username@domain

      if m = uri.match /^([^@]+)@([^@:]+)$/
        domain = m[2]

        addresses = yield dns.resolveSrvAsync '_sip._udp.' + domain
        trace 'Addresses', addresses
        for address in addresses
          do (address) ->
            result.push address

      dns_cache.set uri, result
      result

Provisioning cache
==================

    prov_cache = LRU
      max: 200
      maxAge: 20 * 1000

    get_prov = seem (prov,key) ->

Use cache if available

      val = prov_cache.get key
      return val if val?

Use database otherwise

      val = yield prov
        .get key
        .catch (error) ->
          {}

      prov_cache.set key, val
      val

    @server_pre = (ctx) ->
      cfg = ctx.cfg
      debug "server_pre, ctx = ", ctx

      socket = dgram.createSocket 'udp4'

      socket.on 'error', (error) ->
        debug "Socket error: #{error}"

      socket.on 'listening', ->
        address = socket.address()
        debug "Listening for SUBSCRIBE messages on #{address.address}:#{address.port}"

Handle SUBSCRIBE messages
=========================

      socket.on 'message', ->
        args = arguments
        Promise.resolve()
        .then ->
          on_message.apply ctx, args
        .catch (error) ->
          debug "on_message: #{error}\n#{error.stack}"

      on_message = seem (msg,rinfo) ->
        debug "Received #{msg.length} bytes message from #{rinfo.address}:#{rinfo.port}"

        content = msg.toString 'ascii'
        trace 'Received message', content

        ua =
          send: (msg) ->
            message = msg.toString()
            trace 'ua:send', message

Send our response (200 OK) back to the IP and port the message come from.

            socket.send message, 0, message.length, rinfo.port, rinfo.address

          newTransaction: (transaction) ->
            @transactions[transaction.type][transaction.id] = transaction

          transactions:
              nist: {}
              nict: {}
              ist: {}
              ict: {}

The parser returns an IncomingRequest for a SUBSCRIBE message.

        request = Parser.parseMessage content, ua
        return unless request? and request.method is 'SUBSCRIBE' and request.event?.event is 'message-summary'

        transaction = new NonInviteServerTransaction request, ua

Try to recover the number and the endpoint from the message.

        number = request.ruri?.user ? request.from?.uri?.user
        endpoint = request.headers['X-Ccnq3-Endpoint']?[0]?.raw

        trace 'SUBSCRIBE', {number, endpoint}

Recover the number-domain from the endpoint.

        {number_domain} = yield get_prov cfg.prov, "endpoint:#{endpoint}"

        user_id = "#{number}@#{number_domain}"

        trace 'SUBSCRIBE', {number_domain,user_id}

Recover the local-number's user-database.

        {user_database} = yield get_prov cfg.prov, "number:#{user_id}"

Record the Event header, dialog, etc. in a LRU-cache so that they may be used in NOTIFY messages.

        # FIXME

Ready to send a notification

        db_uri = cfg.userdb_base_uri + '/' + user_database

        trace 'SUBSCRIBE', {user_database,db_uri}

We set the Expires header so that the client is forced to re-SUBSCRIBE regularly.
FIXME: RFC3265 section 3.1.1 requires that our Expires be <= to the one requested in the SUBSCRIBE message.

        try
          request.reply 200, 'OK', ['Expires: 600']
        catch error
          debug "SUBSCRIBE request.reply: #{error}\n#{error.stack}"
        request = null

Create a User object and use it to send the notification.

        ###
        user = new User ctx, user_id, user_database, db_uri
        yield send_notification_to user
          .catch (error) ->
            debug "SUBSCRIBE send_notification_to: #{error}\n#{error.stack}", user_id
        user = null
        ###
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
        trace 'send_notification_to', {total_rows}

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
          yield notify uri, to, total_rows

Static endpoint

        else
          if via?
            to = [user.id,endpoint].join '@'
            uri = [user.id,via].join '@'
            debug 'Notifying endpoint', {endpoint,uri,to}
            yield notify uri, to, total_rows
          else
            debug 'No `via` for static endpoint, skipping.'

        debug 'send_notification_to done', user.id
        return

Notify a specific URI
=====================

We route based on the URI domain, as per RFC.

      notify = seem (uri,to,total_rows) ->
        debug 'notify', {uri,to,total_rows}

        addresses = yield resolve uri

        for address in addresses
          do (address) ->
            send_sip_notification uri, to, total_rows, address.port, address.name

        debug 'notify done', {uri,to,total_rows}
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

      debug 'Configured.'
      return
