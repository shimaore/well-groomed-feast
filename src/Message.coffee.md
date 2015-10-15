Usage:

- Existing message with the given ID:

```
new Message(ctx, User, id)
```

- New message:

```
new Message(ctx, User).create()
```


    class Message

      format: 'wav'
      min_duration: process.env.MESSAGE_MIN_DURATION ? 5
      max_duration: process.env.MESSAGE_MAX_DURATION ? 300
      the_first_part: 1
      the_last_part: process.env.MAX_PARTS ? 1

      constructor: (@ctx,@user,@id) ->
        @part = @the_first_part

      uri: (name,rev) ->
        @ctx.uri @user,@id,name,rev

      has_part: (part = @part) ->
        name = "part#{part}.#{@format}"
        debug 'has_part', @id, part, @format, name
        @user.db.get @id
        .then (doc) ->
          debug 'has_part', doc._attachments[name]
          doc._attachments[name]?

Record the current part
-----------------------

      start_recording: ->
        debug 'start_recording', @id
        record_seconds = null
        @user.db.get @id
        .then (doc) =>

FIXME: Add 'set', "RECORD_TITLE=Call from #{caller}", "RECORD_DATE=..."

          name = "part#{@part}.#{@format}"
          upload_url = @uri name, doc._rev
          @ctx.record upload_url, @max_duration
        .then (record_seconds) =>
          if record_seconds < @min_duration
            @delete_single_part @part
            .then ->
              0
          else
            record_seconds

Play a recording, optionally collect a digit
------------------------------------------------------------

      play_recording: (this_part = @the_first_part) ->
        debug 'play_recording', @id, this_part
        return unless this_part <= @the_last_part

Might need to add parameters (`url_params`, between `()`) here; names are:
- ext
- nohead (skip querying with HEAD; this is used to cache files)
See `file_open` in mod_httapi.c.

        name = "part#{this_part}.#{@format}"
        url = @uri name
        @has_part this_part
        .then (it_does) =>
          debug 'play_recording', {it_does}
          @ctx.play url if it_does

Keep playing if no user interaction

        .then (choice) =>
          @play_recording this_part+1 if not choice?
          choice

Delete parts
------------

      delete_all_parts: ->
        debug 'delete_all_parts', @id
        @user.db.get @id
        .then (doc) =>
          # Remove all attachments
          doc._attachments = {}
          @user.db.put doc

      delete_single_part: (this_part) ->
        debug 'delete_single_part', this_part
        @user.db.get @id
        .then (doc) =>
          name = "part#{this_part}.#{@format}"
          @user.db.removeAttachment @id, name, doc.rev

Post-recording menu
-------------------

      post_recording: ->
        debug 'post_recording', @id

Check whether the attachment exists (it might be deleted if it doesn't match the minimum duration)

        @has_part @part
        .then (it_does) =>
          debug 'post_recording', {it_does}
          unless it_does
            it =
              cuddly.ops "Could not record message part", {message_id:@id,user_id:@user.id}
              .then ->
                @ctx.action 'phrase', "could not record please try again"
              .then =>
                @start_recording()
            return it

FIXME The default FreeSwitch prompts only allow for one-part messages, while we allow for multiple.

          @ctx.get_choice 'phrase:voicemail_record_file_check:1:2:3'
          .then (choice) =>
            switch choice

Play

              when "1"
                @play_recording @the_first_part
                .then =>
                  @post_recording()

Delete

              when "3"
                @delete_all_parts()
                .then =>
                  @part = @the_first_part
                  @start_recording()
                  .then =>
                    @post_recording()

Append

              when "4" # Keep recording
                if @part < @the_last_part
                  @part++
                  @start_recording()
                else
                  # FIXME: notify that the last part has been recorded
                  @post_recording()

Save

              when "2"
                return

              else
                @post_recording()

      # Play the message enveloppe
      play_enveloppe: (index) ->
        debug 'play_enveloppe', @id
        @user.db.get @id
        .then (doc) =>
          user_timestamp = @user.time doc.timestamp
          @ctx.play "phrase:'message received:#{index+1}:#{doc.caller_id}:#{user_timestamp}'"

      # Create a new voicemail record in the database
      create: ->
        id_timestamp = timestamp()
        @id = 'voicemail:' + id_timestamp + @ctx.data.variable_uuid
        debug 'create', @id
        msg =
          type: "voicemail"
          _id: @id
          timestamp: id_timestamp
          box: 'new' # In which box is this message?
          caller_id: @ctx.source
          recipient: @ctx.destination

        # If the user simply hungs up this is the only event we will receive.
        @ctx.call.on 'freeswitch_disconnect_notice', =>
          @notify()

        # Create new CDB record to hold the voicemail metadata
        @user.db.put msg
        .catch (e) =>
          debug "Could not create message: #{e}."
          cuddly.csr "Could not create message: #{e}"
          @ctx.error 'MSG-180'

      notify: ->
        debug 'notify', @user.id, @id
        return unless @ctx.cfg.notifiers?
        for name, notifier of @ctx.cfg.notifiers
          do (name,notifier) =>
            notifier @user, @id
            .catch (error) ->
              debug "Notifier #{name} error: #{error}"
              cuddly.csr "Notifier #{name} error: #{error}"
        return

      remove: ->
        debug 'remove', @id
        @user.db.get @id
        .then (doc) =>
          doc.box = 'trash'
          @user.db.put doc
        .then =>
          @notify()
        .then =>
          @ctx.action 'phrase', 'voicemail_ack,deleted'

      save: ->
        debug 'save', @id
        @user.db.get @id
        .then (doc) =>
          doc.box = 'saved'
          @user.db.put doc
        .then =>
          @notify()
        .then =>
          @ctx.action 'phrase', 'voicemail_ack,saved'

    module.exports = Message
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Message"
    cuddly = (require 'cuddly') "#{pkg.name}:Message"

    timestamp = -> new Date().toJSON()
