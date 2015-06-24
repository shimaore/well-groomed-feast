#!/usr/bin/env coffee
This is the ccnq4 voicemail server.

`mod_httapi` is used to record or play
files to/from remote CouchDB. (This avoids having to download
audio prompts, or store then upload recorded messages.)

Voicemail content is stored as .wav PCM mono 16 bits (generated
by FreeSwitch) which can then be transcoded.
(RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, mono 8000 Hz)

    Messaging = require '../src/Messaging'
    seconds = 1000

    @include = ->

      messaging = new Messaging @

      switch @destination

        when 'record'
          debug "Record for #{user}@#{number_domain}"
          msg = null
          user = null
          @linger()
          .then ->
            # Keep the call opened for a little while.
            @once 'esl_linger'
            .delay 20*seconds
            .then ->
              @exit()
            @command 'answer'
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
          debug "Inbox for #{user}@#{number_domain}"
          user = null
          @command 'answer'
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
          debug "Main for #{user}@#{number_domain}"
          user = null
          @command 'answer'
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
          play 'The system had an internal error. Please hang up and try again. Error KWAO-6812'
