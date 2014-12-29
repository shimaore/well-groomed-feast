    Promise = require 'bluebird'
    fs = Promise.promisifyAll require 'fs'
    mkfifo = require './mkfifo'
    stream_as_promised = require 'stream-as-promised'
    request = require 'superagent-as-promised'
    assert = require 'assert'

    winston = require 'winston'
    logger = winston

Usage: `play_from_url.call(call,fifo_path,download_url).then (res) -> @command ...`

    module.exports = (fifo_path,download_url,streaming = true) ->
      assert fifo_path?, 'Missing fifo_path'
      assert download_url?, 'Missing download_url'

      logger.info "play_from_url", {fifo_path,download_url,streaming}

      cleanup = ->
        logger.info "play_from_url: Cleanup #{fifo_path}"
        fs.unlinkAsync fifo_path

      @once 'PLAYBACK_STOP', cleanup

When streaming, first start the proxy on the fifo

      stream = null
      req = null

      create_stream = ->
        s = fs.createWriteStream fifo_path
        stream = stream_as_promised s
        req = request.get download_url
        req.pipe s
        return

      if streaming
        it =
          mkfifo fifo_path
          .then ->
            create_stream()

Download the file

      else
        it =
          Promise.resolve()
          .then ->
            create_stream()
            req

      it = it.bind this

      the_result = null

      it
      .then ->

Play the file, expecting a single digit, storing the outcome in (FreeSwitch) variable `choice`.

        @command 'play_and_get_digits', "1 1 1 1000 # #{fifo_path} silence_stream://250 choice \\d 1000"

      .then (res) ->
        logger.info 'play_from_url: Playing command completed'
        the_result = res
      .catch (error) ->
        logger.error "play_from_url: #{error}"
      .then ->
        the_result
