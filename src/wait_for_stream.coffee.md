    Promise = require 'bluebird'

    module.exports = (stream) ->

      new Promise (resolve,reject) ->
        try
          stream.on 'error', (error) ->
            reject error

          stream.on 'end', ->
            resolve fifo_stream
        catch error
          reject error
