Usage:

- Existing message with the given ID:

```
new Message(ctx, User, id)
```

- New message:

```
new Message(ctx, User).create()
```

    assert = require 'assert'

    sum_of = (a) ->
      (v for k,v of a).reduce ((x,y) -> x+y), 0

    assert.equal 0, sum_of {}
    assert.equal 0, sum_of {a:0}
    assert.equal 0, sum_of {a:-3,b:3}
    assert.equal 10, sum_of {a:4,b:3,c:2,d:1}

    Formats = require './Formats'

    class Message

      min_duration: parseInt process.env.MESSAGE_MIN_DURATION ? 2
      max_duration: parseInt process.env.MESSAGE_MAX_DURATION ? 300
      the_first_part: 1
      the_last_part: parseInt process.env.MAX_PARTS ? 9

      constructor: (@ctx,@user,@id) ->
        @part = @the_first_part
        @done = false

      uri: (name,rev) ->
        @ctx.voicemail_uri @user,@id,name,rev

      get_part: (part = @part) ->
        doc = await @user.db.get @id

        Formats.find doc, "part#{part}"

Record the current part
-----------------------

      start_recording: ->
        debug 'start_recording', @id
        record_seconds = null
        doc = await @user.db.get @id
        doc.durations ?= {}

        await @ctx.set RECORD_TITLE:"Call from #{doc.caller_id}"

        name = Formats.name "part#{@part}"
        upload_url = @uri name, doc._rev
        record_seconds = parseInt (await @ctx.prompt.record upload_url, @max_duration), 10
        debug 'start_recording: message saved', {record_seconds}
        if (isNaN record_seconds) or record_seconds < @min_duration
          await @delete_single_part @part
          0
        else
          doc = await @user.db.get @id
          doc.durations ?= {}
          doc.durations[name] = record_seconds
          doc.duration = sum_of doc.durations
          await @user.db.put doc
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

        name = await @get_part this_part
        if name
          url = @uri name
          debug 'play_recording', {name,url}
          choice = await @ctx.prompt.play url

Keep playing if no user interaction

        if not choice?
          @play_recording this_part+1
        else
          choice

Delete parts
------------

      delete_all_parts: ->
        debug 'delete_all_parts', @id
        doc = await @user.db.get @id
        # Remove all attachments
        doc._attachments = {}
        doc.durations = {}
        doc.duration = 0
        await @user.db.put doc

      delete_single_part: (this_part) ->
        debug 'delete_single_part', this_part
        doc = await @user.db.get @id
        doc.durations ?= {}
        for format in @format
          name = "part#{this_part}.#{format}"
          delete doc.durations[name] if name of doc.durations
          doc.duration = sum_of doc.durations
          {rev} = await @user.db.put doc
          @user.db
            .removeAttachment @id, name, rev
            .catch (error) ->
              debug "remove attachment: #{error}", {@id,name,rev}
        return

Post-recording menu
-------------------

      post_recording: ->
        debug 'post_recording', @id
        return if @done

Check whether the attachment exists (it might be deleted if it doesn't match the minimum duration)

        it_does = await @get_part @part
        debug 'post_recording', {it_does}
        unless it_does
          await debug.ops "Could not record message part", {message_id:@id,user_id:@user.id}
          await @ctx.action 'phrase', "could not record please try again"
          await @start_recording()
          return

FIXME The default FreeSwitch prompts only allow for one-part messages, while we allow for multiple.

        choice = await @ctx.prompt.get_choice 'phrase:voicemail_record_file_check:1:2:3'
        switch choice

Play

          when "1"
            debug 'post_recording: play'
            await @play_recording @the_first_part
            @post_recording()

Delete

          when "3"
            debug 'post_recording: delete'
            await @delete_all_parts()
            @part = @the_first_part
            await @start_recording()
            @post_recording()

Append

          when "4" # Keep recording
            debug 'post_recording: append'
            if @part < @the_last_part
              @part++
              await @start_recording()
            else
              # FIXME: notify that the last part has been recorded
              @post_recording()

Save

          when "2"
            debug 'post_recording: save'
            return

          else
            @post_recording()

Play the message enveloppe
--------------------------

      play_enveloppe: (index) ->
        debug 'play_enveloppe', @id
        doc = await @user.db.get @id
        user_timestamp = @user.time doc.timestamp
        @ctx.prompt.play "phrase:'message received:#{index+1}:#{doc.caller_id}:#{user_timestamp}'"

Create a new voicemail record in the database
---------------------------------------------

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

If the user simply hungs up this is the only event we will receive.
Note: now that we process `linger` properly this might be moved into `post_recording`, but the added complexity is probably not worth it.

        @ctx.call.once 'cleanup_linger', foot =>
          debug 'Disconnect Notice', @id
          @done = true
          await sleep 15000
          heal @notify 'create'
          return

Create new CDB record to hold the voicemail metadata

        @user.db.put msg
        .catch (e) =>
          debug.csr "Could not create message: #{e}", @id
          @ctx.prompt.error 'MSG-180'

      notify: (flag) ->
        debug 'notify', flag, @user.id, @id
        return unless @ctx.cfg.notifiers?
        for name, notifier of @ctx.cfg.notifiers
          await do (name,notifier) =>
            notifier @user, @id, flag
            .catch (error) ->
              debug.csr "Notifier #{name} error: #{error.stack ? error}"
        return

      remove: ->
        debug 'remove', @id
        doc = await @user.db.get @id
        doc.box = 'trash'
        await @user.db.put doc
        heal @notify 'remove'
        @ctx.action 'phrase', 'voicemail_ack,deleted'

      save: ->
        debug 'save', @id
        doc = await @user.db.get @id
        doc.box = 'saved'
        await @user.db.put doc
        heal @notify 'save'
        @ctx.action 'phrase', 'voicemail_ack,saved'

The forward operation is a bit complex since it requires to:

- locate and open the database for the destination user (I guess this can be done with `locate_user`);
- copy the JSON document from the original db to the destination db;
- copy the attachment(s);
- optionally add a new attachment (comment) in the destination (but not the source) db.

There used to be code properly handling "more than one attachment" in this module; however some of it was removed for ccnq4. Make sure all places know how to handle multi-part voicemails.

      forward: (destination) ->
        messaging = new Messaging @ctx
        {user} = await messaging.retrieve_number destination

        if not user?
          ## Blabla destination does not exist, try again
          return false

        @ctx.source = @user.number
        @ctx.destination = user.number

        target = new Message @ctx, user
        await target.create()

Record an additional part, which should be put as the first part (and the remaining parts should be shifted).

        await target.user.play_prompt()
        await target.start_recording()
        await target.post_recording()

So, mostly, we're left with:

        # Granted, downloading all the attachment in memory is not a good idea.

        doc = await @user.db.get @id,
          attachments:true
          binary:true
        new_doc = await target.user.db.get target.id,
          attachments:true
          binary:true

Append the parts of `doc` to the ones in `new_doc`.

        sorted_attachments = (d) ->
          Object.keys(d._attachments).sort()

        parts = []

        gather_parts = (d) ->
          for name in sorted_attachments(d) when m = name.match /^part\d+\.(\S+)$/
            parts.push
              extension: m[1]
              value: d._attachments[name]
              duration: d.durations[name]

We need to rename the parts in `doc` so that they follow the ones in new_doc.

        gather_parts new_doc
        gather_parts doc

        new_doc._attachments = {}
        new_doc.durations = {}
        for part, i in parts
          name = "part#{i+target.the_first_part}.#{part.extension}"
          new_doc._attachments[name] = part.value
          new_doc.durations[name] = part.duration

        new_doc.duration = sum_of new_doc.durations

        await target.user.db.put new_doc

Do not leak.

        await target.user.close_db()
        target.user = null
        target = null

        true

    module.exports = Message
    pkg = require '../package.json'
    {debug,foot,heal} = (require 'tangible') "#{pkg.name}:Message"
    sleep = (timeout) -> new Promise (resolve) -> setTimeout resolve, timeout
    Messaging = require './Messaging'

    timestamp = -> new Date().toJSON()
