The plan
========

    chai = require 'chai'
    chai.should()

    Promise = require 'bluebird'
    path = require 'path'
    seconds = 1000

    zappa = require 'zappajs'
    FS = require 'esl'
    logger = require 'winston'
    logger.remove logger.transports.Console
    logger.add logger.transports.Console, timestamp:on

    record_to_url = require '../src/record_to_url'
    play_from_url = require '../src/play_from_url'

We need a shared directory between us and FreeSwitch to save the contents (aka `fifo_path`).

    fifo_dir = '/opt/freeswitch/recordings'

Create a FreeSwitch image with our scripts

    describe 'Play and Record', ->
      web =
        host: '127.0.0.1'
        port: 3000

      fs =
        host: '127.0.0.1'
        sip_port: 5062
        event_port: 8022
        server_port: 7002
        fifo_path: path.join fifo_dir, 'some.fifo.wav'
        url: "http://#{web.host}:#{web.port}/content.wav"

      before ->
        @timeout 9*seconds

        web.server = zappa web.host, web.port, ->
          @get '/content.wav', ->
            logger.info 'play-record tester: GET /content.wav'
            @res.type web.content_type
            @send web.content
          @put '/content.wav', ->
            logger.info 'play-record tester: PUT /content.wav'
            web.content_type = @req.get 'content-type'
            logger.info 'play-record tester', typeof @body
            web.content = new Buffer @body
            @res.status 200

        fs.server = FS.server ->
          logger.info "FS.server: Call in" #, @data
          @trace (o) ->
            delete o.body
            logger.info 'FS.server', o
          switch @data['Channel-Destination-Number']
            when 'record'
              @linger()
              .then ->
                @command 'answer'
              .then ->
                logger.info "FS.server: Calling record_to_url"
                record_to_url.call this, fs.our_fifo_dir, fs.url
              .then (res) ->
                logger.info 'FS.server: Response after record_to_url', res
            when 'play'
              @linger()
              .then ->
                @command 'answer'
              .then ->
                logger.info "FS.server: Calling play_from_url"
                play_from_url.call this, fs.fifo_dir, fs.url
              .then (res) ->
                logger.info 'FS.server: play_from_url', res
        fs.server.listen fs.server_port

and start it

      it 'should save a recording', (done) ->
        @timeout 12*seconds
        logger.info "play-record tester: Starting..."
        call_uuid = null

        fs.client = FS.client ->
          ###
          @trace (o) ->
            logger.info 'FS.client', o
          ###
          @api 'sofia status'
          .then ->
            @api "originate sofia/test-sender/sip:record@#{fs.host}:#{fs.sip_port} &park"
          .then (res) ->
            logger.info "FS.client: Recording"
            call_uuid = res.uuid
          .delay 7*seconds
          .then ->
            @hangup_uuid call_uuid
          .delay 3*seconds
          .then ->
            fs.client.end()
            web.should.have.property 'content'
            # web.content.byteLength().should.be.greater.than ...
          .then done
          .catch done
        fs.client.connect fs.event_port, fs.host

Call the recording profile and record
Call the playing profile and play
