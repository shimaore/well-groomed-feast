    class User

      min_pin_length: process.env.MIN_PIN_LENGTH ? 6
      default_timezone: process.env.DEFAULT_TIMEZONE ? null
      voicemail_dir: '/opt/freeswitch/messages'

      constructor: (@ctx,@db_uri,@id) ->
        @db = new PouchDB @db_uri
        @init_db()

      init_db: ->
        debug 'init_db'
        # FIXME: inject the proper view(s)

      uri: (p) ->
        if p?
          [@db_uri,p].join '/'
        else
          @db_uri

      voicemail_settings: ->
        debug 'voicemail_settings'
        # Memoize
        if @vm_settings?
          return Promise.resolve @vm_settings

        @db.get 'voicemail_settings'
        .catch (error) =>

1. Debug un max

          debug "VM Box is not available", {user_id:@id}
          cuddly.csr "VM Box is not available", {user_id:@id}

2. Message qui dit d'appeler le support

          @ctx.error 'USR-41'
        .then (doc) =>
          @vm_settings = doc # Memoize

Convert a timestamp (ISO string) to a local timestamp (ISO string)

      time: (t) ->
        debug 'time'
        timezone = @vm_settings.timezone ? User.default_timezone
        tz_mod = null
        if timezone?
          try
            tz_mod = require "timezone/#{timezone}"
          catch e
            debug "Error loading timezone/#{timezone}"
            tz_mod = null
        if tz_mod?
          tz t, timezone, tz_mod, '%FT%T%z'
        else
          t

      play_prompt: ->
        debug 'play_prompt'
        @voicemail_settings()
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
        debug 'authenticate', {attempts}
        attempts ?= 3
        if attempts <= 0
          return @ctx.error()

        vm_settings = null

        @voicemail_settings()
        .then (_settings) =>
          vm_settings = _settings
          @ctx.get_pin() if vm_settings.pin?
        .then (pin) ->
          if vm_settings.pin?
            if pin isnt vm_settings.pin
              Promise.reject new Error "Wrong PIN"
        .then =>
          @ctx.action 'set', "language=#{vm_settings.language}" if vm_settings.language?
        .then =>
          @ctx.action 'phrase', 'voicemail_hello'
        .catch (error) =>
          @authenticate attempts-1

      new_messages: ->
        debug 'new_messages'
        the_rows = null
        @db.query 'voicemail/new_messages'
        .then ({rows}) =>
          the_rows = rows
          @ctx.action 'phrase', "voicemail_message_count,#{rows.length}:new"
        .then ->
          the_rows

      saved_messages: ->
        debug 'saved_messages'
        the_rows = null
        @db.query 'voicemail/saved_messages'
        .then ({rows}) ->
          the_rows = rows
          @action 'phrase', "voicemail_message_count,#{rows.length}:saved"
        .then ->
          the_rows

      navigate_messages: (rows,current) ->
        debug 'navigate_messages', {rows,current}
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
              true

            else # including "1" meaning "listen"
              @navigate_messages rows, current

        msg.play_enveloppe current
        .then (choice) =>
          return choice if choice?
          msg.play_recording()
        .then (choice) =>
          return choice if choice?
          @ctx.get_choice "phrase:'voicemail_listen_file_check:1:2:3'"
        .then (choice) =>
          navigate choice if choice?
        .catch (error) ->
          debug "navigate_messages: #{error}"

Default navigation is: read next message

          if error.choice
            @navigate_messages rows, current+1
          else
            throw error

      config_menu: ->
        debug 'config_menu'
        @ctx.get_choice "phrase:'voicemail_config_menu:1:2:3:4:5'"
        .then (choice) =>
          switch choice
            when "1"
              @record_greeting()
              .then =>
                @config_menu()
            when "3"
              @record_name()
              .then =>
                @config_menu()
            when "4"
              @change_password()
              .then =>
                @config_menu()
            when "5"
              @main_menu()
            else
              @config_menu()
        .catch (error) =>
          debug "config_menu: #{error}"
          @ctx.error 'USR-211'

      main_menu: ->
        debug 'main_menu'
        @ctx.get_choice "phrase:'voicemail_menu:1:2:3:4'"
        .then (choice) =>
          debug 'main_menu', {choice}
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
              @ctx.goodbye()
            else
              @main_menu()
        .catch (error) =>
          debug "main_menu: #{error}"
          @ctx.error 'USR-238'

      record_something: (that,phrase) ->
        debug 'record_something', {that,phrase}
        rev = null
        @db.get 'voicemail_settings'
        .then (doc) =>
          rev = doc._rev
          @ctx.action 'phrase', phrase
        .then =>
          upload_url = @db_uri + '/voicemail_settings/' + that + '.' + message_format + '?rev=' + rev
          @ctx.record upload_url

      record_greeting: ->
        debug 'record_greeting'
        @record_something 'prompt', 'voicemail_record_greeting'
        .catch (error) =>
          debug "record_greeting: #{error}"
          @record_greeting()

      record_name: ->
        debug 'record_name'
        @record_something 'name', 'voicemail_record_name'
        .catch (error) =>
          debug "record_name: #{error}"
          @record_name()

      change_password: ->
        debug 'change_password'
        new_pin = null

        @ctx.get_new_pin min:User.min_pin_length
        .then (pin) =>
          new_pin = pin
          unless new_pin? and new_pin.length >= User.min_pin_length
            @ctx
            .action 'phrase', 'vm_say,too short'
            .then =>
              Promise.reject new Error 'Password too short'
        .then =>
          @db.get 'voicemail_settings'
        .then (vm_settings) =>
          vm_settings.pin = new_pin
          @db.put vm_settings
        .then =>
          delete @vm_settings # remove memoized value
          @ctx.action 'phrase', 'vm_say,thank you'
        .catch (error) =>
          debug "change_password: #{error}"
          @change_password()

    module.exports = User
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:User"
    cuddly = (require 'cuddly') "#{pkg.name}:User"

    tz = require 'timezone'
    Promise = require 'bluebird'
    PouchDB = require 'pouchdb'
    Message = require './Message'