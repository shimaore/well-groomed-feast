Usage:

- Existing message with the given ID:

```
new Message(ctx, User, id)
```

- New message:

```
new Message(ctx, User).create()
```

    seem = require 'seem'

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

      has_part: seem (part = @part) ->
        name = "part#{part}.#{@format}"
        debug 'has_part', @id, part, @format, name
        doc = yield @user.db.get @id
        debug 'has_part', doc._attachments[name]
        doc._attachments[name]?

Record the current part
-----------------------

      start_recording: seem ->
        debug 'start_recording', @id
        record_seconds = null
        doc = yield @user.db.get @id

FIXME: Add 'set', "RECORD_TITLE=Call from #{caller}", "RECORD_DATE=..."

        name = "part#{@part}.#{@format}"
        upload_url = @uri name, doc._rev
        record_seconds = parseInt yield @ctx.record upload_url, @max_duration
        if (isNaN record_seconds) or record_seconds < @min_duration
          yield @delete_single_part @part
          0
        else
          record_seconds

Play a recording, optionally collect a digit
------------------------------------------------------------

      play_recording: seem (this_part = @the_first_part) ->
        debug 'play_recording', @id, this_part
        return unless this_part <= @the_last_part

Might need to add parameters (`url_params`, between `()`) here; names are:
- ext
- nohead (skip querying with HEAD; this is used to cache files)
See `file_open` in mod_httapi.c.

        name = "part#{this_part}.#{@format}"
        url = @uri name
        it_does = yield @has_part this_part
        debug 'play_recording', {it_does}
        choice = yield @ctx.play url if it_does

Keep playing if no user interaction

        @play_recording this_part+1 if not choice?
        choice

Delete parts
------------

      delete_all_parts: seem ->
        debug 'delete_all_parts', @id
        doc = @user.db.get @id
        # Remove all attachments
        doc._attachments = {}
        @user.db.put doc

      delete_single_part: seem (this_part) ->
        debug 'delete_single_part', this_part
        doc = yield @user.db.get @id
        name = "part#{this_part}.#{@format}"
        @user.db.removeAttachment @id, name, doc.rev
        @user.db
          .removeAttachment @id, name, doc.rev
          .catch (error) ->
            debug "remove attachment: #{error}", {@id,name,doc.rev}

Post-recording menu
-------------------

      post_recording: seem ->
        debug 'post_recording', @id

Check whether the attachment exists (it might be deleted if it doesn't match the minimum duration)

        it_does = @has_part @part
        debug 'post_recording', {it_does}
        unless it_does
          yield cuddly.ops "Could not record message part", {message_id:@id,user_id:@user.id}
          yield @ctx.action 'phrase', "could not record please try again"
          yield @start_recording()
          return

FIXME The default FreeSwitch prompts only allow for one-part messages, while we allow for multiple.

        choice = yield @ctx.get_choice 'phrase:voicemail_record_file_check:1:2:3'
        switch choice

Play

          when "1"
            yield @play_recording @the_first_part
            @post_recording()

Delete

          when "3"
            yield @delete_all_parts()
            @part = @the_first_part
            yield @start_recording()
            @post_recording()

Append

          when "4" # Keep recording
            if @part < @the_last_part
              @part++
              yield @start_recording()
            else
              # FIXME: notify that the last part has been recorded
              @post_recording()

Save

          when "2"
            return

          else
            @post_recording()

      # Play the message enveloppe
      play_enveloppe: seem (index) ->
        debug 'play_enveloppe', @id
        doc = yield @user.db.get @id
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
          debug 'Disconnect Notice', @id
          @notify 'create'

        # Create new CDB record to hold the voicemail metadata
        @user.db.put msg
        .catch (e) =>
          debug "Could not create message: #{e}.", @id
          cuddly.csr "Could not create message: #{e}"
          @ctx.error 'MSG-180'

      notify: (flag) ->
        debug 'notify', @user.id, @id
        return unless @ctx.cfg.notifiers?
        for name, notifier of @ctx.cfg.notifiers
          do (name,notifier) =>
            notifier @user, @id, flag
            .catch (error) ->
              debug "Notifier #{name} error: #{error}"
              cuddly.csr "Notifier #{name} error: #{error}"
        return

      remove: seem ->
        debug 'remove', @id
        doc = yield @user.db.get @id
        doc.box = 'trash'
        yield @user.db.put doc
        @notify 'remove'
        @ctx.action 'phrase', 'voicemail_ack,deleted'

      save: seem ->
        debug 'save', @id
        doc = yield @user.db.get @id
        doc.box = 'saved'
        yield @user.db.put doc
        @notify 'save'
        @ctx.action 'phrase', 'voicemail_ack,saved'

    module.exports = Message
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Message"
    cuddly = (require 'cuddly') "#{pkg.name}:Message"

    timestamp = -> new Date().toJSON()
