    dgram = require 'dgram'
    Promise = require 'bluebird'
    seem = require 'seem'
    dns = Promise.promisifyAll require 'dns'
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:mwi_notifier"

    assert = require 'assert'

    @name = "#{pkg.name}:mwi_notifier"
    @include = (ctx) ->
      cfg = ctx.cfg
      cfg.notifiers ?= []

      assert cfg.prov?, 'Missing prov'

      unless cfg.voicemail?.notifier_port?
        debug 'Missing `voicemail.notifier_port`'
        return

      socket = dgram.createSocket 'udp4'

      send_notification_to = seem (user) ->
        debug 'send_notification_to', user

        doc = yield cfg.prov.get "number:#{user.id}"
        if not doc.user_database? then return

        send_sip_notification = seem (target_port,target_name)->
          {total_rows} = yield user.db.query 'voicemail/new_messages'

          body = new Buffer """
            Message-Waiting: #{if total_rows > 0 then 'yes' else 'no'}
          """

          # FIXME no tag, etc.
          headers = new Buffer """
            NOTIFY sip:#{endpoint} SIP/2.0
            Via: SIP/2.0/UDP #{target_name}:#{target_port};branch=0
            Max-Forwards: 2
            To: <sip:#{endpoint}>
            From: <sip:#{endpoint}>
            Call-ID: #{Math.random()}
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

        endpoint = doc.endpoint
        d = endpoint.match /^([^@]+)@([^@]+)$/
        if d
          domain_name = d[2]
          addresses = yield dns.resolveSrv '_sip._udp.' + domain_name
          for address in addresses
            do (address) ->
              send_sip_notification address.port, address.name
        else
          # Currently no MWI to static endpoints
          return


      socket.on 'message', (msg,rinfo) ->
        content = msg.toString 'ascii'
        if r = content.match /^SUBSCRIBE sip:(\d+)@/
          send_notification_to r[1]

      socket.bind cfg.voicemail.notifier_port ? 7124

      cfg.notifiers.push send_notification_to
      debug 'Configured.'
