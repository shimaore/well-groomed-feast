    class User

      min_pin_length: process.env.MIN_PIN_LENGTH ? 6
      default_timezone: process.env.DEFAULT_TIMEZONE ? null
      voicemail_dir: '/opt/freeswitch/messages'

      constructor: (@ctx,@db_uri,@id) ->
        @db = new PouchDB @db_uri
        @init_db()

      init_db: ->
        FIXME: inject the proper view(s)

      mention_error: ->
        play 'The system encountered an internal error. Please hang up and try again. If this happens again, please call support.'

      uri: (p) ->
        if p?
          [@db_uri,p].join '/'
        else
          @db_uri

      voicemail_settings: ->
        # Memoize
        if @vm_settings?
          return Promise.resolve @vm_settings

        @db.get 'voicemail_settings'
        .catch (error) =>
          logger.error "VM Box for #{@id} is not available from #{@db_uri}."
          @ctx.action 'phrase', 'vm_say,sorry'
          .then =>

1. Debug un max

            cuddly.csr "VM Box is not available", {user_id:@id}

2. Message qui dit d'appeler le support

            @mention_error()
          return
        .then =>
          @vm_settings = vm_settings # Memoize

Convert a timestamp (ISO string) to a local timestamp (ISO string)

      time: (t) ->
        timezone = @vm_settings.timezone ? User.default_timezone
        tz_mod = null
        if timezone?
          try
            tz_mod = require "timezone/#{timezone}"
          catch e
            logger.error "Error loading timezone/#{timezone}"
            tz_mod = null
        if tz_mod?
          tz t, timezone, tz_mod, '%FT%T%z'
        else
          t

      play_prompt: ->
        @voicemail_settings
        .then (vm_settings) =>

User-specified prompt

          if vm_settings._attachments?["prompt.#{message_format}"]
            @play @db_uri + "/voicemail_settings/prompt.#{message_format}"

User-specified name

          else if vm_settings._attachments?["name.#{message_format}"]
            @play @db_uri + "/voicemail_settings/name.#{message_format}"
            .then =>
              @ctx.action 'phrase', 'voicemail_unavailable', next

Default prompt

          else
            @ctx.action 'phrase', "voicemail_play_greeting,#{@id}", next

        .then =>
          if vm_settings.do_not_record
            false
          else
            @ctx.action 'phrase', 'voicemail_record_message'
            .then ->
              true

      authenticate: (attempts) ->
        attempts ?= 3
        if attempts <= 0
          return goodbye()

        @voicemail_settings
        .then (vm_settings) =>
          wrap_cb = =>
            if vm_settings.language?
              call.command 'set',  "language=#{vm_settings.language}", (call) ->
                call.command 'phrase', 'voicemail_hello', cb
            else
              call.command 'phrase', 'voicemail_hello', cb

          if vm_settings.pin?
            @ctx.get_pin()
            .then (pin) ->
              if call.body.variable_pin is vm_settings.pin
                do wrap_cb
              else
                @authenticate call, cb, attempts-1
          else
            do wrap_cb

      new_messages: ->
        the_rows = null
        @db.view 'voicemail', 'new_messages'
        .bind @ctx
        .then ({rows}) ->
          the_rows = rows
          @ctx.action 'phrase', "voicemail_message_count,#{rows.length}:new"
        .then ->
          the_rows

      saved_messages: ->
        the_rows = null
        @db.view 'voicemail', 'saved_messages'
        .bind call
        .then ({rows}) ->
          the_rows = rows
          @command 'phrase', "voicemail_message_count,#{rows.length}:saved"
        .then ->
          the_rows

      navigate_messages: (rows,current) ->
        # Exit once we reach the end or there are no messages, etc.
        if current < 0 or not rows? or current >= rows.length
          return

        msg = new Message @ctx, @, rows[current].id
        navigate = (key) =>
          switch key
            when "7"
              if current is 0
                @ctx.action 'phrase', 'no previous message'
                .then =>
                  @navigate_messages rows, current
              else
                @navigate_messages rows, current-1

            when "9"
              if current is rows.length-1
                @ctx.action 'phrase', 'no next message'
                .then =>
                  @navigate_messages rows, current
              else
                @navigate_messages rows, current+1

            when "3"
              msg.remove()
              .then =>
                @navigate_messages rows, current+1

            when "2"
              msg.save()
              .then =>
                @navigate_messages rows, current+1

            when "0"
              Promise.resolve()

            else # including "1" meaning "listen"
              @navigate_messages rows, current

        msg.play_enveloppe current
        .then (choice) =>
          if choice?
            return choice
          msg.play_recording()
        .then (choice) =>
          if choice?
            return choice
          @ctx.get_choice "phrase:'voicemail_listen_file_check:1:2:3:4:5:6'"
        .then (choice) ->
          navigate choice
        .catch ->
          # Default navigation is: read next message
          @navigate_messages rows, current+1


      config_menu: ->
        @ctx.get_choice "phrase:'voicemail_config_menu:1:2:3:4:5'"
        .then (choice) =>
          switch choice
            when "1"
              @record_greeting()
            when "3"
              @record_name()
            when "4"
              @change_password()
            when "5"
              @main_menu()
            else
              @config_menu()
        .catch =>
          @config_menu()

      main_menu: ->
        @ctx.get_choice "phrase:'voicemail_menu:1:2:3:4'"
        .then (choice) ->
          switch choice
            when "1"
              @new_messages()
              .then (rows) =>
                @navigate_messages rows, 0
              .then =>
                @main_menu()
            when "2"
              @saved_messages()
              .then (rows) =>
                @navigate_messages rows, 0
              .then =>
                @main_menu()
            when "3"
              @config_menu()
            when "4"
              goodbye.apply call
            else
              @main_menu call
        .catch =>
          @main_menu call

      record_something: (that,phrase,call) ->
        @db.rev 'voicemail_settings', (e,r,b) =>
          if e?
            @main_menu call
          rev = b.rev

          call.command 'phrase', phrase, (call) =>
            tmp_file = User.voicemail_dir + '/' + that + Math.random() + '.' + message_format
            upload_url = @db_uri + '/voicemail_settings/' + that + '.' + message_format + '?rev=' + rev
            record_to_url call, tmp_file, upload_url, (error,call) =>
              if error
                @record_greeting call
              else
                @main_menu call


      record_greeting: ->
        @record_something 'prompt', 'voicemail_record_greeting'

      record_name: ->
        @record_something 'name', 'voicemail_record_name'

      change_password: ->
        @ctx.get_new_pin min:User.min_pin_length
        .then (res) ->
          new_pin = res.body.variable_new_pin
          if new_pin? and new_pin.length >= User.min_pin_length
            @db.get 'voicemail_settings'
            .then (vm_settings) =>
              vm_settings.pin = new_pin
              @db.put vm_settings
            .then =>
              delete @vm_settings # remove memoized value
              @ctx.action 'phrase', 'vm_say,thank you'
            .catch =>
              @change_password()
            .then =>
              @main_menu()
          else
            @ctx.action 'phrase', 'vm_say,too short'
            .then =>
              @change_password()

    module.exports = User
    pkg = require '../package.json'
    cuddly = (require 'cuddly') "#{pkg.name}:User"

    tz = require 'timezone'
    Promise = require 'bluebird'
