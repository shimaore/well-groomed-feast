    module.exports = write_some_streaming_content = (stream) ->
      w = stream_as_promised stream
      chunk = new Buffer 8000/(1000*msec/ptime)
      Promise
      .delay ptime
      .then ->
        w.stream.writeAsync chunk
      .delay ptime
      .then ->
        w.stream.writeAsync chunk
      .delay ptime
      .then ->
        w.stream.writeAsync chunk
      .delay ptime
      .then ->
        w.stream.writeAsync chunk
      .delay ptime
      .then ->
        w.stream.writeAsync chunk
      .then ->
        w.stream.end()

    Promise = require 'bluebird'
    stream_as_promised = require 'stream-as-promised'
    msec = 1
    ptime = 20*msec
