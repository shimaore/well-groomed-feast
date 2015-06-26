This is the ccnq4 voicemail server.

`mod_httapi` is used to record or play
files to/from remote CouchDB. (This avoids having to download
audio prompts, or store then upload recorded messages.)

Voicemail content is stored as .wav PCM mono 16 bits (generated
by FreeSwitch) which can then be transcoded.
(RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 8000 Hz)

    Messaging = require '../src/Messaging'
    seconds = 1000

    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:voicemail"
    @name = "#{pkg.name}/middleware/voicemail"

    @include = ->

      messaging = new Messaging this

      debug "Routing incoming call to #{@destination}"

      switch @destination

        when 'record'
          msg = null
          user = null
          @linger()
          .then =>
            # Keep the call opened for a little while.
            @once 'esl_linger'
            .delay 20*seconds
            .then ->
              @exit()
            @action 'answer'
          .then =>
            @action 'set', "language=#{@cfg.announcement_language}"
          .then ->
            messaging.locate_user()
          .then (_user) ->
            user = _user
            msg = new Message call, user, db_uri
            msg.create()
          .then ->
            user.play_prompt()
          .then ->
            if do_recording
              msg.start_recording call
            else
              messaging.goodbye()

        when 'inbox'
          user = null
          @action 'answer'
          .then =>
            @action 'set', "language=#{@cfg.announcement_language}"
          .then ->
            locate_user()
          .then (_user) ->
            user = _user
            user.authenticate()
          .then ->
Enumerate messages
            user.new_messages()
          .then (rows) ->
            user.navigate_messages rows, 0
          .then ->
Go to the main menu after message navigation
            user.main_menu call


        when 'main'
          user = null
          @action 'answer'
          .then =>
            @action 'set', "language=#{@cfg.announcement_language}"
          .then ->
            messaging.gather_user()
          .then (_user) ->
            user = _user
            user.authenticate()
          .then ->
Present the main menu
            user.main_menu call

        else
          # FIXME say something
          @action 'pre_answer'
          .then =>
            @action 'set', "language=#{@cfg.announcement_language}"
          .then =>
            @action 'phrase', 'spell,KWAO-6812'
          .then =>
            @action 'phrase', 'spell,KWAO-6812'
