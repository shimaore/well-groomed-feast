The plan
========

    chai = require 'chai'
    chai.should()

    Promise = require 'bluebird'
    _exec = Promise.promisify (require 'child_process').exec
    path = require 'path'
    current_dir = path.dirname __filename
    process.chdir current_dir
    exec = (cmd,fail_if_stderr = false) ->
      logger.info cmd
      _exec cmd
      .then ([stdout,stderr]) ->
        logger.info 'Command returned', {cmd,stdout,stderr}
        throw new Error stderr if stderr and fail_if_stderr
      .catch (error) ->
        logger.error "#{cmd} failed: #{error}"
        throw error
    pkg = require '../package.json'
    seconds = 1000

    logger = require 'winston'
    logger.remove logger.transports.Console
    logger.add logger.transports.Console, timestamp:on

    record_to_url = require '../src/record_to_url'
    play_from_url = require '../src/play_from_url'

We need a shared directory between us and FreeSwitch to save the contents (aka `fifo_path`).

    fifo_dir = '/opt/freeswitch/recordings'

Create a FreeSwitch image with our scripts

    describe 'Play and Record', ->
      docker =
        image: "#{pkg.name}-test-image"
        container: "#{pkg.name}-test-container"
        name: "#{pkg.name}-test-instance"
        dir: 'live'

and start it

      it 'should work', ->
        @timeout 90*seconds
        Promise.resolve()
        .then -> exec "tar cf #{docker.dir}/src.tar -C .. src/ package.json"
        .then -> exec "docker build -t #{docker.image} #{docker.dir}"
        .then -> exec "docker kill #{docker.container}"
        .catch -> true
        .delay 2*seconds
        .then -> exec "docker rm #{docker.container}"
        .catch -> true
        .then -> exec "docker run -d --net=host --name #{docker.container} #{docker.image}"
        .then ->
          logger.info "play-record tester: Waiting for FreeSwitch to be ready."
        .delay 4*seconds
        # .then -> exec "docker exec #{docker.container} npm test"
        # FIXME apparently docker exec doesn't propagate the exit code (tested with mocha directly as well).
        .then -> exec "docker exec #{docker.container} npm test", true

Call the recording profile and record
Call the playing profile and play
