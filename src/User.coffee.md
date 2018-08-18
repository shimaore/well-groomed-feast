    Formats = require './Formats'

User
====

    class User

      min_pin_length: parseInt process.env.MIN_PIN_LENGTH ? 6
      default_timezone: process.env.DEFAULT_TIMEZONE ? null
      voicemail_dir: '/opt/freeswitch/messages'

      constructor: (@ctx,@id,@database,@db_uri) ->
        [@number,@number_domain] = @id.split '@'
        @db = new PouchDB @db_uri

Inject the views into the database.
Note: this requires the application to be database admin, which is OK.

      init_db: ->
        debug 'init_db'
        doc = await @db.get(couchapp._id).catch -> {}
        doc[k] = v for own k,v of couchapp
        await @db.put(doc).catch -> true
        return

      close_db: ->
        await @db.close?()
        @db = null

      uri: (name,rev) ->
        @ctx.voicemail_uri this, 'voicemail_settings', name, rev

      voicemail_settings: (no_error = false) ->
        debug 'voicemail_settings'
        # Memoize
        if @vm_settings?
          return Promise.resolve @vm_settings

        @db.get 'voicemail_settings'
        .catch (error) =>

Debug as much as we can.

          debug.csr "VM Box is not available", {user_id:@id}

Tell the user to call support.

          return {} if no_error
          @ctx.prompt.error 'USR-41'
        .then (doc) =>
          @vm_settings = doc # Memoize

Convert a timestamp (ISO string) to a local timestamp (ISO string)

* doc.voicemail_settings.timezone Timezone for voicemail.

      timezone: ->
        @vm_settings.timezone ? @default_timezone

      time: (t) ->
        debug 'time'
        timezone = @timezone()
        if timezone?
          moment.tz(t, timezone).format()
        else
          moment(t).format()

Playing prompt before recording a voice message
-----------------------------------------------

      play_prompt: ->
        debug 'play_prompt'
        vm_settings = await @voicemail_settings()

        find = (name) ->
          Formats.find vm_settings, name

### Selecting a prompt

The prompt to be played may be one of:
- a recorded message;
- an announceiment with the recorded full name of the recipient;
- or a generic announcement.

The user might indicate which announcement they'd like to play; otherwise an announcement is automatically selected based on the available recordings.

        switch

          when vm_settings.prompt is 'prompt' and f = find 'prompt'
            await @ctx.prompt.play @uri f

          when vm_settings.prompt is 'name' and f = find 'name'
            await @ctx.prompt.play @uri f
            await @ctx.prompt.phrase 'voicemail_unavailable'

          when vm_settings.prompt is 'default'
            await @ctx.prompt.phrase "voicemail_play_greeting,#{@id}"

          when f = find 'prompt'
            await @ctx.prompt.play @uri f

          when f = find 'name'
            await @ctx.prompt.play @uri f
            await @ctx.prompt.phrase 'voicemail_unavailable'

          else
            await @ctx.prompt.phrase "voicemail_play_greeting,#{@id}"

* doc.voicemail_settings.prompt (optional string, either 'prompt', 'name', or 'default') Indicate how the user would like the caller to be prompted to leave a message. If not present, the choice is made based on which attachment is present.
* doc.voicemail_settings._attachments.prompt (prompt.wav) User-specified voicemail prompt. Used if present.
* doc.voicemail_settings._attachments.name (name.wav) User-specified voicemail name. Used if the prompt is not present.

### Actually recording the message

The user might opt for an announcement-only voicemailbox, in which case the caller does not have the option to leave a message.

* doc.voicemail_settings.do_not_record If true, do not record voicemail messages.

        if @vm_settings.do_not_record
          return false

        await @ctx.action 'phrase', 'voicemail_record_message'
        return true

      authenticate: (attempts) ->
        debug 'authenticate', {attempts}

As long as we went through `locate_user` these should be provided.

        assert @ctx.session.number?, 'Missing session number data'

        attempts ?= 3
        if attempts <= 0
          return @ctx.prompt.error()

* doc.voicemail_settings Document found in the user database. Contains parameters for that user's voicemail box.

        vm_settings = await @voicemail_settings()

        authenticated = false

If the user requested not to be queried for a PIN, we authenticate using the endpoint.

* doc.voicemail_settings.ask_pin If false, bypass authentication by PIN and validate access using the endpoint.

        if vm_settings.ask_pin is false

... however let's make sure we don't compare `null` with `null`, which would lead us to allow entry to non-validated calls.

          if @ctx.session.endpoint?.endpoint?
            authenticated = @ctx.session.number.endpoint is @ctx.session.endpoint.endpoint

Otherwise, authentication can only happen with the PIN.

* doc.voicemail_settings.pin The (numeric) PIN to access voicemail.

        if not authenticated
          if vm_settings.pin?
            pin = await @ctx.prompt.get_pin()
            authenticated = pin is vm_settings.pin

* doc.voicemail_settings.language Language used inside voicemail.

        if authenticated
          await @ctx.set language: vm_settings.language if vm_settings.language?
          await @ctx.prompt.phrase 'voicemail_hello'
        else
          @authenticate attempts-1

      new_messages: ->
        debug 'new_messages'
        {rows} = await @db.query 'voicemail/new_messages'
        await @ctx.action 'phrase', "voicemail_message_count,#{rows.length}:new"
        rows

      saved_messages: ->
        debug 'saved_messages'
        {rows} = await @db.query 'voicemail/saved_messages'
        await @ctx.action 'phrase', "voicemail_message_count,#{rows.length}:saved"
        rows

      navigate_messages: (rows,current) ->
        debug 'navigate_messages', {rows:rows?.length,current}
        # Exit once we reach the end or there are no messages, etc.
        if current < 0 or not rows? or current >= rows.length
          return

        msg = new Message @ctx, @, rows[current].id

        choice  = await msg.play_enveloppe current
        choice ?= await msg.play_recording()
        choice ?= await @ctx.prompt.get_choice "phrase:'voicemail_listen_file_check:1:2:3:4'"

        switch choice

Listen to the current message

          when '1'
            @navigate_messages rows, current

Jump to the previous message

          when "7"
            if current is 0
              await @ctx.prompt.phrase 'no previous message'
              @navigate_messages rows, current
            else
              @navigate_messages rows, current-1

Jump to the next message

          when "9"
            if current is rows.length-1
              await @ctx.prompt.phrase 'no next message'
              @navigate_messages rows, current
            else
              @navigate_messages rows, current+1

Delete

          when "3"
            await msg.remove()
            @navigate_messages rows, current+1

Save

          when "2"
            await msg.save()
            @navigate_messages rows, current+1

Forward

          when "4"

Gather recipient's number

            destination = await @ctx.prompt.get_number
              file: 'phrase:voicemail_forward_message_enter_extension:#'
              invalid_file: 'phrase:voicemail_invalid_extension'

Attempt to forward

            if destination?
              unless await msg.forward destination
                await @ctx.prompt.phrase 'voicemail_invalid_extension'

Repeat message so that the user knows where to continue

            @navigate_messages rows, current

Return to the main menu

          when "0"
            true

Default navigation is: read next message or return to the main menu

          else
            if current is rows.length-1
              return
            @navigate_messages rows, current+1

      config_menu: (attempt = 3) ->
        debug 'config_menu'
        return if not @ctx.call? or @ctx.call.closed
        choice = await @ctx.prompt.get_choice "phrase:'voicemail_config_menu:1:2:3:4:5'"
        switch choice
          when "1"
            await @record_greeting()
            @config_menu()
          when "3"
            await @record_name()
            @config_menu()
          when "4"
            await @change_password()
            @config_menu()
          when "5"
            @main_menu()
          else
            if attempt > 0
              @config_menu attempt-1
            else
              @main_menu()

      main_menu: (attempt = 7) ->
        debug 'main_menu'
        return if not @ctx.call? or @ctx.call.closed
        choice = await @ctx.prompt.get_choice "phrase:'voicemail_menu:1:2:3:4'"
        debug 'main_menu', {choice}
        switch choice
          when "1"
            rows = await @new_messages()
            await @navigate_messages rows, 0
            @main_menu()
          when "2"
            rows = await @saved_messages()
            await @navigate_messages rows, 0
            @main_menu()
          when "3"
            @config_menu()
          when "4"
            @ctx.prompt.goodbye()
          else
            if attempt > 0
              @main_menu attempt-1
            else
              @ctx.prompt.goodbye()

* doc.voicemail_settings._attachments Contains prompts for the user's voicemail.

      record_something: (that,phrase,min_duration = 3) ->
        debug 'record_something', {that,phrase}
        doc = await @db.get 'voicemail_settings'
        rev = doc._rev
        await @ctx.prompt.phrase phrase
        name = Formats.name that
        upload_url = @uri name, rev
        recorded = await @ctx.prompt.record upload_url
        if recorded < min_duration
          await @ctx.prompt.phrase 'vm_say,too short'
          @record_something that,phrase
        else
          @ctx.prompt.phrase 'vm_say,thank you'

      record_greeting: ->
        debug 'record_greeting'
        @record_something 'prompt', 'voicemail_record_greeting'
        .catch (error) =>
          debug "record_greeting: #{error}"
          @ctx.prompt.error 'USR-263'

      record_name: ->
        debug 'record_name'
        @record_something 'name', 'voicemail_record_name', 1
        .catch (error) =>
          debug "record_name: #{error}"
          @ctx.prompt.error 'USR-270'

      change_password: ->
        debug 'change_password'
        return if not @ctx.call? or @ctx.call.closed

        get_pin = =>
          pin = await @ctx.prompt.get_new_pin min:@min_pin_length
          if pin?
            if pin.length >= @min_pin_length
              return pin
            else
              await @ctx.prompt.phrase 'vm_say,too short'
          get_pin()

        new_pin = await get_pin()
        vm_settings = await @db.get 'voicemail_settings'
        vm_settings.pin = new_pin
        await @db.put vm_settings
        delete @vm_settings # remove memoized value
        @ctx.prompt.phrase 'vm_say,thank you'

    module.exports = User
    pkg = require '../package.json'
    debug = (require 'tangible') "#{pkg.name}:User"
    assert = require 'assert'

    moment = require 'moment-timezone'
    PouchDB = require 'ccnq4-pouchdb'
      .defaults
        ajax:
          forever: true
          timeout: 10000
        skip_setup: true
    Message = require './Message'

    couchapp = require './couchapp'
