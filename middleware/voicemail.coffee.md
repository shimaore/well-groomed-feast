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

      messaging = new Messaging this

      debug "Routing incoming call to #{@destination}"

      switch @destination

        when 'inbox'
          yield @action 'answer'
          yield @action 'set', "language=#{@cfg.announcement_language}"
          user = yield messaging.locate_user @source
          debug 'Authenticating', user
          yield user.authenticate()
          debug 'Enumerate messages'
          rows = yield user.new_messages()
          yield user.navigate_messages rows, 0
          debug 'Go to the main menu after message navigation'
          user.main_menu()

        when 'main'
          yield @action 'answer'
          yield @action 'set', "language=#{@cfg.announcement_language}"
          user = yield messaging.gather_user()
          yield user.authenticate()
          debug 'Present the main menu'
          user.main_menu()

        else

Keep the call opened for a little while.

          @call.once 'freeswitch_linger'
          .delay 20*seconds
          .then ->
            @exit()
          .catch (error) ->
            debug "linger: #{error}"

          yield @call.linger()
          yield @action 'answer'
          yield @action 'set', "language=#{@cfg.announcement_language}"
          user = yield messaging.locate_user @destination
          msg = new Message this, user
          yield msg.create()
          do_recording = yield user.play_prompt()
          if do_recording
            yield msg.start_recording()
            yield msg.post_recording()
          @goodbye()
