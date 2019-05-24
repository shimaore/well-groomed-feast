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
    {debug} = (require 'tangible') @name

`esl` will wait 4000ms, while our own `Message` will wait 3000ms.
In any case closing too early will cause issues with email notifications.

    close_delay = 60*seconds

    finish = (user) ->
      debug 'finish'
      handler = ->
        debug 'finish - closing db'
        try await user?.close_db()
        user = null
      setTimeout handler, close_delay

    @include = ->

      return unless @session?.direction is 'voicemail'

      messaging = new Messaging this

      debug "Routing incoming call to #{@destination}"

      switch @destination

        when 'inbox'
          try
            await @action 'answer'
            return unless @session?
            await @set language: @session.language ? @cfg.announcement_language

            debug 'Locate user', @source
            user = await messaging.locate_user @source

            debug 'Authenticate', user
            await user.authenticate()

            debug 'Enumerate messages'
            rows = await user.new_messages()
            await user.navigate_messages rows, 0

            debug 'Go to the main menu after message navigation'
            await user.main_menu()

          catch error
            debug.error 'inbox', error

          finally
            finish user
            user = null
            rows = null

        when 'main'

          try
            await @action 'answer'
            return unless @session?
            await @set language: @session.language ? @cfg.announcement_language

            debug 'Retrieve and locate user'
            user = await messaging.gather_user()

            debug 'Authenticate', user.id
            await user.authenticate()

            debug 'Present the main menu'
            await user.main_menu()

          catch error
            debug.error 'main', error

          finally
            finish user
            user = null

        else

          try
            await @action 'answer'
            return unless @session?
            await @set language: @session.language ? @cfg.announcement_language

            debug 'Locate user', @destination
            user = await messaging.locate_user @destination

            msg = new Message this, user
            await msg.create()

            do_recording = await user.play_prompt()
            if do_recording
              await msg.start_recording()
              await msg.post_recording()

            await @prompt.goodbye()

          catch error
            debug.error 'default', error

          finally

            finish user
            user = null
            msg = null

      messaging = null

      debug 'Done.'
      return
