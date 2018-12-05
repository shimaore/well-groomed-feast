Notify a specific URI
=====================

    pkg = require '../package'
    {debug,foot} = (require 'tangible') "#{pkg.name}:notify"

    resolve = require './resolve'

We route based on the URI domain, as per RFC.

    module.exports = notify = (socket,uri,to,new_messages,saved_messages) ->
      debug 'notify', {uri,to,new_messages,saved_messages}

      addresses = await resolve uri

      for address in addresses
        do (address) ->
          send_sip_notification socket, uri, to, new_messages,saved_messages, address.port, address.name

      debug 'notify done', {uri,to,new_messages,saved_messages}
      return

Send notification packet to an URI at a given address and port
==============================================================

    send_sip_notification = foot (socket,uri,to,new_messages,saved_messages,target_port,target_name) ->
      debug 'Send SIP notification', {uri,target_port,target_name}

[RFC3842](https://tools.ietf.org/html/rfc3842)

      body = Buffer.from """
        Message-Waiting: #{if new_messages > 0 then 'yes' else 'no'}
        Voice-Message: #{new_messages}/#{saved_messages}

      """

      headers = Buffer.from """
        PUBLISH sip:#{uri} SIP/2.0
        Via: SIP/2.0/UDP #{target_name}:#{target_port};branch=0
        Max-Forwards: 2
        To: <sip:#{to}>
        From: <sip:#{to}>;tag=#{Math.random()}
        Call-ID: #{pkg.name}-#{Math.random()}
        CSeq: 1 PUBLISH
        Event: message-summary
        Subscription-State: active
        Content-Type: application/simple-message-summary
        Content-Length: #{body.length}
        \n
      """.replace /\n/g, "\r\n"

      message = Buffer.allocUnsafe headers.length + body.length
      headers.copy message
      body.copy message, headers.length

      await new Promise (resolve,reject) ->
        socket.send message, 0, message.length, target_port, target_name, (error) ->
          if error
            reject error
          else
            resolve()
          return
      debug 'Sent SIP notification'
      return
