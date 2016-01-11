    seem = require 'seem'

    class User

      min_pin_length: process.env.MIN_PIN_LENGTH ? 6
      default_timezone: process.env.DEFAULT_TIMEZONE ? null
      voicemail_dir: '/opt/freeswitch/messages'

      constructor: (@ctx,@id,@database,@db_uri) ->
        @db = new PouchDB @db_uri
        @init_db()

Inject the views into the database.
Note: this requires the application to be database admin, which is OK.

      init_db: seem ->
        debug 'init_db'
        doc = yield @db.get(couchapp._id).catch -> {}
        doc[k] = v for own k,v of couchapp
        yield @db.put(doc).catch -> true

      uri: (name,rev) ->
        @ctx.uri this, 'voicemail_settings', name, rev

      voicemail_settings: (no_error = false) ->
        debug 'voicemail_settings'
        # Memoize
        if @vm_settings?
          return Promise.resolve @vm_settings

        @db.get 'voicemail_settings'
        .catch (error) =>

Debug as much as we can.

          debug "VM Box is not available", {user_id:@id}
          cuddly.csr "VM Box is not available", {user_id:@id}

Tell the user to call support.

          return {} if no_error
          @ctx.error 'USR-41'
        .then (doc) =>
          @vm_settings = doc # Memoize

Convert a timestamp (ISO string) to a local timestamp (ISO string)

      time: (t) ->
        debug 'time'
        timezone = @vm_settings.timezone ? @default_timezone
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

          if vm_settings._attachments?["prompt.#{Message::format}"]
            @ctx.play @uri "prompt.#{Message::format}"

User-specified name

          else if vm_settings._attachments?["name.#{Message::format}"]
            @ctx.play @uri "name.#{Message::format}"
            .then =>
              @ctx.action 'phrase', 'voicemail_unavailable'

Default prompt

          else
            @ctx.action 'phrase', "voicemail_play_greeting,#{@id}"

        .then =>
          if @vm_settings.do_not_record
            false
          else
            @ctx.action 'phrase', 'voicemail_record_message'
            .then ->
              true

      authenticate: seem (attempts) ->
        debug 'authenticate', {attempts}

As long as we went through `locate_user` these should be provided.

        assert @ctx.session.number?, 'Missing session number data'
        assert @ctx.session.endpoint?, 'Missing session endpoint data'

        attempts ?= 3
        if attempts <= 0
          return @ctx.error()

        vm_settings = yield @voicemail_settings()

        authenticated = false

If the user requested not to be queried for a PIN, we authenticate using the endpoint.

        if vm_settings.ask_pin is false

... however let's make sure we don't compare `null` with `null`.

          if @ctx.session.endpoint.endpoint?
            authenticated = @ctx.session.number.endpoint is @ctx.session.endpoint.endpoint

Otherwise, authentication can only happen with the PIN.

        if not authenticated
          if vm_settings.pin?
            pin = yield @ctx.get_pin()
            authenticated = pin is vm_settings.pin

        if authenticated
          yield @ctx.action 'set', "language=#{vm_settings.language}" if vm_settings.language?
          yield @ctx.action 'phrase', 'voicemail_hello'
        else
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
        .then ({rows}) =>
          the_rows = rows
          @ctx.action 'phrase', "voicemail_message_count,#{rows.length}:saved"
        .then ->
          the_rows

      navigate_messages: (rows,current) ->
        debug 'navigate_messages', {rows,current}
        # Exit once we reach the end or there are no messages, etc.
        if current < 0 or not rows? or current >= rows.length
          return Promise.resolve()

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
        .catch (error) =>
          debug "navigate_messages: #{error}"

Default navigation is: read next message

          if error.choice
            @navigate_messages rows, current+1
          else
            throw error

      config_menu: (attempt = 3) ->
        debug 'config_menu'
        return if @ctx.call.closed
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
              if attempt > 0
                @config_menu attempt-1
              else
                @main_menu()
        .catch (error) =>
          debug "config_menu: #{error}"
          @ctx.error 'USR-211'

      main_menu: (attempt = 7) ->
        debug 'main_menu'
        return if @ctx.call.closed
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
              if attempt > 0
                @main_menu attempt-1
              else
                @ctx.goodbye()
        .catch (error) =>
          debug "main_menu: #{error}"
          if error.choice
            @ctx.goodbye()
          else
            @ctx.error 'USR-238'

      record_something: seem (that,phrase) ->
        debug 'record_something', {that,phrase}
        doc = yield @db.get 'voicemail_settings'
        rev = doc._rev
        yield @ctx.action 'phrase', phrase
        upload_url = @uri "#{that}.#{Message::format}", rev
        recorded = yield @ctx.record upload_url
        if recorded < 3
          @ctx.action 'phrase', 'vm_say,too short'
          yield @record_something that,phrase
        else
          @ctx.action 'phrase', 'vm_say,thank you'

      record_greeting: ->
        debug 'record_greeting'
        @record_something 'prompt', 'voicemail_record_greeting'
        .catch (error) =>
          debug "record_greeting: #{error}"
          @ctx.error 'USR-263'

      record_name: ->
        debug 'record_name'
        @record_something 'name', 'voicemail_record_name'
        .catch (error) =>
          debug "record_name: #{error}"
          @ctx.error 'USR-270'

      change_password: ->
        debug 'change_password'
        new_pin = null

        get_pin = =>
          @ctx.get_new_pin min:@min_pin_length
          .then (pin) =>
            return get_pin() unless pin?
            new_pin = pin
            debug 'change_password', {new_pin}
            return if new_pin?.length >= @min_pin_length
            @ctx
            .action 'phrase', 'vm_say,too short'
            .then =>
              get_pin()

        get_pin()
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

    module.exports = User
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:User"
    cuddly = (require 'cuddly') "#{pkg.name}:User"
    assert = require 'assert'

    tz = require 'timezone'
    Promise = require 'bluebird'
    PouchDB = require 'pouchdb'
    Message = require './Message'

    couchapp = require './couchapp'
