    Promise = require 'bluebird'
    execAsync = Promise.promisify (require 'child_process').exec

    module.exports = (fifo_path) ->
      execAsync "rm -f '#{fifo_path}'; /usr/bin/mkfifo -m 0666 '#{fifo_path}'", stdio:['ignore','ignore','pipe']
