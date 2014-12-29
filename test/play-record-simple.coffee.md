Simple (white-box) tests for record and play
============================================

    chai = require 'chai'
    chai.should()

    Promise = require 'bluebird'
    fs = Promise.promisifyAll require 'fs'
    stream_as_promised = require 'stream-as-promised'
    path = require 'path'
    emulator = require './esl_emulator'
    Response = require 'esl/lib/response'
    write_some_streaming_content = require './write_some_streaming_content'
    zappa = require 'zappajs'

    fifo_dir = path.dirname module.filename

    sec = 1000

These tests validate the base functioning by `emulating` ESL.

Record To URL
=============

    describe 'White-box test of record_to_url', ->

      class RecordSocket
        write: (text) ->
          {cmd,headers,body} = emulator.parse text

          if headers['execute-app-name'] is 'record'
            emulator.emits @response, headers
            filename = headers['execute-app-arg'].split(' ')[0]
            console.log "*** RecordSocket.write: write stream #{filename}"
            write_some_streaming_content fs.createWriteStream filename
            .then =>
              @response.emit 'RECORD_STOP'

          else if text.match /^sendmsg/
            emulator.emits @response, headers

        end: ->
          # console.log '*** Socket.end()'
          return

      record_to_url = require '../src/record_to_url'

The test bascically waits for the code to submit the `@command 'record', '<file-name><space>...'`, create/saves the file, and waits for it to be submitted.

      file_name = 'foo.wav'

Create the web service

      web =
        host: '127.0.0.1'
        port: 3002
        ref: {}

      server = ->
        port = web.port++
        parse_express_raw_body = (require 'parse-express-raw-body')()
        rec =
          url: "http://#{web.host}:#{port}/content.wav"
        rec.app = zappa web.host, port, ->
          @put '/content.wav', parse_express_raw_body, ->
            rec.content_type = @req.get 'content-type'
            rec.content = @body
            @json ok:true
        web.ref[port] = rec

      after ->
        for own port, rec of web.ref
          do (rec) -> rec.app.server.close()

      it 'should save the file', ->
        rec = server()
        socket = new RecordSocket()
        response = new Response socket
        # response.trace on
        socket.response = response
        fifo_path = path.join fifo_dir, 'record.some.file.wav'
        record_to_url.call response, fifo_path, rec.url, null, false
        .then ->
          fs.unlinkAsync fifo_path
            .catch -> yes
          rec.should.have.property('content_type').eql 'audio/vnd.wave'
          rec.should.have.property('content').length 8000/20*5

      it 'should pipe the file', ->
        rec = server()
        socket = new RecordSocket()
        response = new Response socket
        # response.trace on
        socket.response = response
        fifo_path = path.join fifo_dir, 'record.some.fifo.wav'
        record_to_url.call response, fifo_path, rec.url, null, true
        .then ->
          fs.unlinkAsync fifo_path
            .catch -> yes
          rec.should.have.property('content_type').eql 'audio/vnd.wave'
          rec.should.have.property('content').length 8000/20*5

Play From URL
=============

    describe.only 'White-box test of play_from_url', ->

      class PlaySocket
        write: (text) ->
          {cmd,headers,body} = emulator.parse text
          emits = => emulator.emits @response, headers

          if headers['execute-app-name'] is 'play_and_get_digits'
            emits()
            filename = headers['execute-app-arg'].split(' ')[5]
            console.log "*** PlaySocket.write: read stream #{filename}"
            console.dir fs.statSync filename
            s = fs.createReadStream filename
            size = 0
            s.on 'data', (chunk) ->
              size += chunk.length
            s.on 'end', =>
              chai.expect(size).to.equal 8000/20*5
              @response.emit 'PLAYBACK_STOP'
            s.resume()

          else if text.match /^sendmsg/
            emits()

        end: ->
          # console.log '*** Socket.end()'
          return

      play_from_url = require '../src/play_from_url'

      file_name = 'foo.wav'

Create the web service

      web =
        host: '127.0.0.1'
        port: 3100
        ref: {}

      server = ->
        port = web.port++
        rec =
          url: "http://#{web.host}:#{port}/content.wav"

        rec.app = zappa web.host, port, ->

          @get '/content.wav', ->
            # Note that the request was received.
            rec.requested = true
            console.log "***** GET on port #{port} *******"
            @res.type 'audio/vnd.wave'
            @res.status 200
            # FIXME is this the proper way to stream out to the client?
            write_some_streaming_content @res
            # Or should I create a stream and pipe it to @res?


        web.ref[port] = rec

      after ->
        for own port, rec of web.ref
          do (rec) -> rec.app.server.close()

      it 'should save the file', ->
        @timeout 5*sec
        rec = server()
        socket = new PlaySocket()
        response = new Response socket
        # response.trace on
        socket.response = response
        fifo_path = path.join fifo_dir, 'play.some.file.wav'
        Promise.delay 3*sec
        .then ->
          play_from_url.call response, fifo_path, rec.url, false
        .then ->
          fs.unlinkAsync fifo_path
            .catch -> yes
          rec.should.have.property('requested').true

      it 'should pipe the file', ->
        @timeout 5*sec
        rec = server()
        socket = new PlaySocket()
        response = new Response socket
        # response.trace on
        socket.response = response
        fifo_path = path.join fifo_dir, 'play.some.fifo.wav'
        Promise.delay 3*sec
        .then ->
          play_from_url.call response, fifo_path, rec.url, true
        .then ->
          fs.unlinkAsync fifo_path
            .catch -> yes
          rec.should.have.property('requested').true
