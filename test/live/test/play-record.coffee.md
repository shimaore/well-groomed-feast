The plan
========

    chai = require 'chai'
    chai.should()

    Promise = require 'bluebird'
    path = require 'path'
    seconds = 1000

    zappa = require 'zappajs'
    parse_express_raw_body = (require 'parse-express-raw-body')()
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

        web.server = zappa web.host, web.port, ->
          @get '/content.wav', ->
            logger.info 'play-record tester: GET /content.wav'
            @res.type web.content_type
            @send web.content
            web.content_requested = true
          @put '/content.wav', parse_express_raw_body, ->
            logger.info 'play-record tester: PUT /content.wav' # , (require 'util').inspect @request
            web.content_type = @req.get 'content-type'
            web.content = @body
            @res.status 200

        fs.server = FS.server ->
          logger.info "FS.server: Call in" #, @data
          ###
          @trace (o) ->
            delete o.body
            logger.info 'FS.server', o
          ###
          switch @data['Channel-Destination-Number']
            when 'record'
              @linger()
              .then ->
                @command 'answer'
              .then ->
                logger.info "FS.server: Calling record_to_url"
                record_to_url.call this, fs.fifo_path, fs.url
              .then (res) ->
                logger.info 'FS.server: Response after record_to_url', res
            when 'play'
              @linger()
              .then ->
                @command 'answer'
              .then ->
                logger.info "FS.server: Calling play_from_url"
                play_from_url.call this, fs.fifo_path, fs.url
              .then (res) ->
                logger.info 'FS.server: play_from_url', res
        fs.server.listen fs.server_port

and start it

      it 'should save a recording', (done) ->
        logger.info "test record: Starting."
        record_time = 10*seconds
        wait_time = 4*seconds
        @timeout record_time+wait_time+1*seconds
        call_uuid = null

        fs.record_client = FS.client ->
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
          .delay record_time
          .then ->
            @hangup_uuid call_uuid
          .delay wait_time
          .then ->
            fs.record_client.end()
            web.should.have.property('content_type').equal 'audio/vnd.wave'
            logger.info "web.content.length = #{web.content.length}"
            web.should.have.property('content').with.length.gt 0
            done()
          .catch done
        fs.record_client.connect fs.event_port, fs.host


Call the recording profile and record
Call the playing profile and play
