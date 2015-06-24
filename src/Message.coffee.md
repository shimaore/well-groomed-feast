Usage:

- Existing message with the given ID:

```
new Message(ctx, User, id)
```

- New message:

```
new Message(ctx, User).create(call,cb)
```


    class Message

      format: 'wav'
      min_duration: process.env.MESSAGE_MIN_DURATION ? 5
      max_duration: process.env.MESSAGE_MAX_DURATION ? 300
      the_first_part: 1
      the_last_part: process.env.MAX_PARTS ? 1

      constructor: (@ctx,@user,@id) ->
        @part = Message.the_first_part

      msg_uri: (p) ->
        if p?
          [@msg_uri(),p].join '/'
        else
          @user.uri @id

      has_part: (part = @part) ->
        @db.get @id
        .then (doc) ->
          doc._attachments["part#{part}.#{Message.format}"]?

Record the current part
-----------------------

      start_recording: ->
        debug 'start_recording', @id
        record_seconds = null
        @db.get @id
        .then (doc) =>
          upload_url = @msg_uri "part#{@part}.#{Message.format}?rev=#{doc._rev}"
          @record upload_url
        .then (res) ->
          record_seconds = res.body.variable_record_seconds
          if record_seconds < Message.min_duration
            request.del upload_url
            record_seconds = 0
        .then ->
          record_seconds
        .catch (error) =>
          # FIXME Remove the attachment from the database?
          # request.del upload_url
          @start_recording()

Play a recording, optionally collect a digit
------------------------------------------------------------

      play_recording: (this_part = Message.the_first_part) ->
        debug 'play_recording', @id, this_part
        url = "#{@msg_uri()}/part#{this_part}.#{Message.format}"
        @has_part this_part
        .then (it_does) ->
          return unless it_does

          download_url = "#{@msg_uri()}/part#{this_part}.#{Message.format}"
          @play download_url
        .then (res) ->
          choice = res.body.variable_choice

Keep playing if no user interaction

          unless choice?
            return @play_recording this_part+1

Otherwise return the user choice.

          choice

        .catch (error) =>
           @play_recording this_part+1

Delete parts
------------

      delete_parts: ->
        debug 'delete_parts', @id
        @db.get @id
        .then (doc) ->
          # Remove all attachments
          doc._attachments = {}
          @db.put doc

Post-recording menu
-------------------

      post_recording: ->

        debug 'post_recording', @id

Check whether the attachment exists (it might be deleted if it doesn't match the minimum duration)

        @has_part @part
        .then (it_does) =>
          unless it_does
            it =
              cuddly.ops "Could not record message part", {message_id:@id,user_id:@user.id}
              .then ->
                @ctx.action 'phrase', "could not record please try again"
              .then =>
                @start_recording()
            return it

          # FIXME The default FreeSwitch prompts only allow for one-part messages, while we allow for multiple.
          @ctx.get_choice 'phrase:voicemail_record_file_check:1:2:3'
          .then (choice) =>
            switch choice
              when "3"
                @delete_parts()
                .then =>
                  @part = Message.the_first_part
                  @start_recording()
              when "1"
                @play_recording Message.the_first_part
                .then =>
                  @post_recording()
              when "2"
                if @part < Message.the_last_part
                  @part++
                  @start_recording()
                else
                  # FIXME: notify that the last part has been recorded
                  @post_recording()
          .catch =>
            @post_recording()

      # Play the message enveloppe
      play_enveloppe: (index) ->
        debug 'play_enveloppe', @id
        @db.get @id
        .then (doc) ->
          user_timestamp = @user.time doc.timestamp
          @ctx.play "phrase:'message received:#{index+1}:#{b.caller_id}:#{user_timestamp}'"
        .then (res) ->
            res.body.variable_choice


      # Create a new voicemail record in the database
      create: ->
        id_timestamp = timestamp()
        @id = 'voicemail:' + id_timestamp + res.body.variable_uuid
        debug 'create', @id
        msg =
          type: "voicemail"
          _id: @id
          timestamp: id_timestamp
          box: 'new' # In which box is this message?
          caller_id: @ctx.source
          recipient: @ctx.destination

        # If the user simply hungs up this is the only event we will receive.
        call.on 'esl_disconnect_notice', =>
          @notify()
        # Wait for linger to finish.
        call.on 'esl_disconnect', =>
          @notify() # Was notify_via_email

        # Create new CDB record to hold the voicemail metadata
        @db.put msg
        .catch (e) =>
          debug "Could not create #{@msg_uri()}"
          @ctx.action 'phrase', 'vm_say,sorry'
          .then ->
            # FIXME what else should we do in this case?

      notify: ->
        debug 'notify', @user.id
        for notifier in @ctx.notifiers
          do (notifier) =>
            notifier @user.id

      remove: ->
        debug 'remove', @id
        @db.get @id
        .then (doc) =>
          doc.box = 'trash'
          @db.put doc
        .then =>
          @notify()
        .then =>
          @ctx.action 'phrase', 'voicemail_ack,deleted', cb

      save: ->
        debug 'save', @id
        @db.get @id
        .then =>
          b.box = 'saved'
          @db.put doc
        .then =>
          @notify()
        .then =>
          @ctx.action 'phrase', 'voicemail_ack,saved', cb

    module.exports = Message
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Message"

    timestamp = -> new Date().toJSON()
