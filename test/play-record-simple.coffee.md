Simple (white-box) tests for record and play
============================================

    chai = require 'chai'
    chai.should()

    Promise = require 'bluebird'
    fs = Promise.promisifyAll require 'fs'
    path = require 'path'
    emulator = require './esl_emulator'

    fifo_dir = path.dirname module.filename

These tests validate the base functioning by `emulating` ESL.

Record To URL
=============

    describe.only 'White-box test of record_to_url', ->

      record_to_url = require '../src/record_to_url'

The test bascically waits for the code to submit the `@command 'record', '<file-name><space>...'`, create/saves the file, and waits for it to be submitted.

      file_name = 'foo.wav'

Create the web service

      web =
        host: '127.0.0.1'
        port: 3002

      fsp =
        fifo_path: path.join fifo_dir, 'some.fifo.wav'

      before ->
        zappa = require 'zappajs'
        parse_express_raw_body = (require 'parse-express-raw-body')()
        web.server = zappa web.host, web.port, ->
          @put '/content.wav', parse_express_raw_body, ->
            web.content_type = @req.get 'content-type'
            web.content = @body
            @json ok:true
        fsp.url = "http://#{web.host}:#{web.port}/content.wav"

      it 'should save the file', ->
        write_some_streaming_content = (p) ->
          # console.log "*** Writing some streaming content to #{p}"
          (require './write_some_streaming_content') fs.createWriteStream p

        Response = require 'esl/lib/response'
        class Socket
          write: (text) ->
            {cmd,headers,body} = emulator.parse text
            emits = => emulator.emits @response, headers

            if headers['execute-app-name'] is 'record'
              write_some_streaming_content headers['execute-app-arg'].split(' ')[0]
              .then emits
              .then =>
                @response.emit 'RECORD_STOP'

            else if text.match /^sendmsg/
              emits()

          end: ->
            # console.log '*** Socket.end()'
            return

        socket = new Socket()
        response = new Response socket
        # response.trace on
        socket.response = response
        record_to_url.call response, fsp.fifo_path, fsp.url
        .then ->
          web.should.have.property('content_type').eql 'audio/vnd.wave'
          web.should.have.property('content').length 8000/20*5
