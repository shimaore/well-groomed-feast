This is the ccnq4 voicemail server.

`mod_httapi` is used to record or play
files to/from remote CouchDB. (This avoids having to download
audio prompts, or store then upload recorded messages.)

Voicemail content is stored as .wav PCM mono 16 bits (generated
by FreeSwitch) which can then be transcoded.
(RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 8000 Hz)

    Messaging = require '../src/Messaging'
    Message = require '../src/Message'
    seconds = 1000

    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:voicemail"
    @name = "#{pkg.name}/middleware/voicemail"
    seem = require 'seem'

    @include = seem ->

      return unless @session.direction is 'voicemail'

      messaging = new Messaging this

      debug "Routing incoming call to #{@destination}"

      switch @destination

        when 'inbox'
          yield @action 'answer'
          yield @action 'set', "language=#{@session.language ? @cfg.announcement_language}"

          debug 'Locate user'
          user = yield messaging.locate_user @source

          debug 'Authenticate', user
          yield user.authenticate()

          debug 'Enumerate messages'
          rows = yield user.new_messages()
          yield user.navigate_messages rows, 0

          debug 'Go to the main menu after message navigation'
          user.main_menu()

        when 'main'

Provide an empty endpoint -- there is none associated with the voicemail main number.

          @session.endpoint ?= {}

          yield @action 'answer'
          yield @action 'set', "language=#{@session.language ? @cfg.announcement_language}"

          debug 'Retrieve and locate user'
          user = yield messaging.gather_user()

          debug 'Authenticate', user
          yield user.authenticate()

          debug 'Present the main menu'
          user.main_menu()

        else

          yield @action 'answer'
          yield @action 'set', "language=#{@session.language ? @cfg.announcement_language}"

          user = yield messaging.locate_user @destination

          msg = new Message this, user
          yield msg.create()

          do_recording = yield user.play_prompt()
          if do_recording
            yield msg.start_recording()
            yield msg.post_recording()

          @goodbye()
