    mkfifo = require '../src/mkfifo'
    Promise = require 'bluebird'
    fs = Promise.promisifyAll require 'fs'

    chai = require 'chai'
    chai.use require 'chai-as-promised'
    chai.should()

    describe 'mkfifo', ->
      fp = '/tmp/foobar.fifo'

Make sure there are no files present before we start.

      before ->
        fs.statAsync fp
        .should.be.rejected

And clean-up after ourselves.

      after ->
        fs.unlinkAsync fp

Create the fifo, check it is a fifo.

      it 'should create a fifo', ->
        mkfifo fp
        .then ->
          fs.statAsync fp
        .then (stat) ->
          stat.isFIFO().should.be.true
