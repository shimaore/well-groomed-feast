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
    @name = "#{pkg.name}:middleware:voicemail"
    {debug,heal} = (require 'tangible') @name
    seem = require 'seem'

`esl` will wait 4000ms, while our own `Message` will wait 3000ms.
In any case closing too early will cause issues with email notifications.

    close_delay = 60*seconds

    finish = (user) ->
      debug 'finish'
      handler = seem ->
        debug 'finish - closing db'
        yield user?.close_db()
        user = null
      setTimeout handler, close_delay

    @include = seem ->

      return unless @session?.direction is 'voicemail'

      messaging = new Messaging this

      debug "Routing incoming call to #{@destination}"

      switch @destination

        when 'inbox'
          try
            yield @action 'answer'
            yield @set language: @session.language ? @cfg.announcement_language

            debug 'Locate user', @source
            user = yield messaging.locate_user @source

            debug 'Authenticate', user
            yield user.authenticate()

            debug 'Enumerate messages'
            rows = yield user.new_messages()
            yield user.navigate_messages rows, 0

            debug 'Go to the main menu after message navigation'
            yield user.main_menu()

          catch error
            debug.error 'inbox', error
            heal @prompt.error 'VM-61'

          finally
            finish user
            user = null
            rows = null

        when 'main'

          try
            yield @action 'answer'
            yield @set language: @session.language ? @cfg.announcement_language

            debug 'Retrieve and locate user'
            user = yield messaging.gather_user()

            debug 'Authenticate', user.id
            yield user.authenticate()

            debug 'Present the main menu'
            yield user.main_menu()

          catch error
            debug.error 'main', error
            heal @prompt.error 'VM-85'

          finally
            finish user
            user = null

        else

          try
            yield @action 'answer'
            yield @set language: @session.language ? @cfg.announcement_language

            debug 'Locate user', @destination
            user = yield messaging.locate_user @destination

            msg = new Message this, user
            yield msg.create()

            do_recording = yield user.play_prompt()
            if do_recording
              yield msg.start_recording()
              yield msg.post_recording()

            yield @prompt.goodbye()

          catch error
            debug.error 'default', error
            heal @prompt.error 'VM-61'

          finally

            finish user
            user = null
            msg = null

      messaging = null

      debug 'Done.'
      return
