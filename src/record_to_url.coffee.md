    Promise = require 'bluebird'
    fs = Promise.promisifyAll require 'fs'
    mkfifo = require './mkfifo'
    wait_for_stream = require './wait_for_stream'
    request = require 'superagent-as-promised'

    winston = require 'winston'
    logger = winston

Usage: `record_to_url.call(call,fifo_path,upload_url).then (res) -> @command ...`

The DTMF that was pressed is available in `call.body.playback_terminator_used` in the callback

    module.exports = (fifo_path,upload_url,message_max_duration = 300,streaming = false) ->

      logger.info "record_to_url", {fifo_path,upload_url,message_max_duration,streaming}

      cleanup = ->
        logger.info "record_to_url: Cleanup #{fifo_path}"
        fs.unlinkAsync fifo_path

There are two ways we might do message recording.
The first one is to stream the audio directly to CouchDB. In that case we create a Unix fifo and send its output to CouchDB.

      stream = null
      req = null

      if streaming
        it =
          mkfifo fifo_path

Start the proxy on the fifo

          .then ->
            logger.info "record_to_url: Starting proxy for #{fifo_path} to #{upload_url}"
            stream = fs.createReadStream fifo_path
            req = request
              .put upload_url
              .type 'audio/vnd.wave' # RFC2361
            stream.pipe req

        wait =
          @once 'RECORD_STOP'

The other one is to first record the audio in a file (using FreeSwitch), then push that file onto CouchDB.

      else
        it = Promise.resolve()

        wait =
          @once 'RECORD_STOP'
          .then ->
            logger.info "record_to_url: Pushing #{fifo_path} to #{upload_url}", fs.statSync fifo_path
            stream = fs.createReadStream fifo_path
            req = request
              .put upload_url
              .type 'audio/vnd.wave' # RFC2361
            stream.pipe req

      it = it.bind this

      the_result = null

      it
      .then ->
        @command 'set', 'RECORD_WRITE_ONLY=true'
      .then ->
        @command 'set', 'playback_terminators=#1234567890'
      .then ->

Play beep to indicate we are ready to record

        @command 'gentones', '%(500,0,800)'
      .then ->
        @command 'record', "#{fifo_path} #{message_max_duration} 20 3"
      .then (res) ->
        logger.info 'record_to_url: Recording command completed'
        the_result = res
        wait
      .then ->
        logger.info 'record_to_url: Wait done'
        req
      .then ->
        logger.info 'record_to_url: Request completed'
        wait_for_stream stream
      .then ->
        logger.info 'record_to_url: Stream completed'
      .then cleanup
      .catch (error) ->
        logger.error "record_to_url: #{error}"
      .then ->
        the_result
