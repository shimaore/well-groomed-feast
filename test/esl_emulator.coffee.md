    @parse = (text) ->
      assert text?, 'Missing text'
      lines = text.split /\n/
      cmd = lines.shift()
      # console.log "*** Socket.write #{JSON.stringify lines}"
      headers = {}
      while (line = lines.shift()) isnt ''
        [key,value] = line.split ': '
        headers[key] = value

      body = lines.join '\n'
      # console.log "*** ESL emulator: parse: #{JSON.stringify {cmd,headers,body}}"
      {cmd,headers,body}

    @emits = (response,headers) ->
      assert response?, 'Missing response'
      assert headers?, 'Missing headers'
      response.emit 'freeswitch_command_reply',
        headers:
          'Reply-Text': '+OK'
      response.emit [
        'CHANNEL_EXECUTE_COMPLETE'
        headers['execute-app-name']
        headers['execute-app-arg']
      ].join ' '

    assert = require 'assert'
