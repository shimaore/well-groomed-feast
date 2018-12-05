    Mustache = require 'mustache'
    {send_mail} = require 'foamy-organization/send-email'
    CouchDB = require 'most-couchdb'

    @name = "well-groomed-feast:middleware:email_notifier"
    debug = (require 'tangible') @name
    assert = require 'assert'
    {inspect} = require 'util'
    sleep = (timeout) -> new Promise (resolve) -> setTimeout resolve, timeout
    ec = encodeURIComponent

    @include = ->
      cfg = @cfg
      {voicemail_uri} = @
      cfg.notifiers ?= {}
      return if cfg.notifiers.email?

      unless cfg.mailer?.SMTP?
        debug 'Missing `mailer.SMTP`'
        return
      unless cfg.voicemail?.sender?
        debug 'Missing `voicemail.sender`'
        return

      prov = new CouchDB cfg.provisioning
      prov.getAttachment = (_id,name) ->
        uri = new URL ec(_id)+'/'+ec(name), @uri+'/'
        @agent
        .get uri.toString()
        .then ({body}) -> body

Template handling
=================

      send_email_notification = (msg,opts) ->
        debug 'send_email_notification', {msg}
        file_name = if opts.attach
            'voicemail_notification_with_attachment'
          else if opts.do_not_record
            'voicemail_notification_do_not_record'
          else
            'voicemail_notification'
        opts.language ?= 'en'

Default templates
-----------------

        default_templates =
          subject: 'New message from {{caller_id}}'
          body: '''
                  You have a new message from {{caller_id}}.
                '''
          html: '''
                  <p>You have a new message from {{caller_id}}.</p>
                '''

Get templates
-------------

        template = {}

        await Promise.all (Object.keys default_templates).map (part) ->
          uri_name = [file_name, opts.language, part].join '.'

          data = await prov
            .getAttachment opts.user.number_domain, uri_name
            .catch -> null

          if data?
            template[part] = data.toString()
            return

### Templates in the provisioning database

          data = await prov
            .getAttachment "config:voicemail", uri_name
            .catch (error) -> null

          if data?
            template[part] = data.toString()
            return

          template[part] = default_templates[part]
          return

Send email out
==============

        debug 'Ready to send.'
        sender = opts.sender ? opts.email
        email_options =
          from: sender
          to: opts.email
          subject: Mustache.render template.subject, msg
          text: Mustache.render template.body, msg
          html: Mustache.render template.html, msg
          attachments: []

        if opts.attach and msg._attachments

          for name, data of msg._attachments
            do (name,data) ->

`data` fields might be: `content_type`, `revpos`, `digest`, `length`, `stub`:boolean

FIXME: Migrate to new `node_mailer` conventions.

              email_options.attachments.push {
                filename: name
                path: voicemail_uri opts.user, msg._id, name, null, true
                contentType: data.content_type
              }

        await send_mail cfg, email_options

Delete record once all data has been emailed.

        if (opts.attach or opts.do_not_record) and opts.send_then_delete
          await opts.user.db.delete msg

        return

API wrapper
===========

      send_notification_to = (user,msg_id) ->
        debug 'send_notification_to', {user: inspect(user), msg_id}

We can only send emails about a specific message.

        return unless msg_id?

FIXME: Sadly enough we don't have yet a way to be notified when the attachment might be available (it is pushed by HTTAPI through our proxy). If we do the retrieval too early, we might miss it. So let's pause for an arbitrary delay and hope the attachment gets uploaded in the time between, therefor allowing us to provide a proper notification.

        await sleep 7*1000

* doc.local_number.voicemail_sender (email address) Address used as the sender for voicemail notifications via email. See doc.voicemail_settings, doc.voicemail_settings.email_notifications . Default: cfg.voicemail.sender
* cfg.voicemail.sender (email address) Address used as default the sender for voicemail notifications via email. See doc.voicemail_settings, doc.voicemail_settings.email_notifications .

        number_doc = await prov.get "number:#{user.id}"
        return if number_doc.disabled
        sender = number_doc.voicemail_sender ? cfg.voicemail.sender
        message = await user.db.get msg_id

We should only email about new messages.

        return unless message.box is 'new'

* doc.voicemail_settings.language (two-letter language string) Language used for email notifications. Default: `en`
* doc.voicemail_settings.send_then_delete (boolean) If true, messages are deleted from the voicemail after the email notification is sent. Default: false.
* doc.voicemail_settings.email_notifications (hash) For each destination email address, provides parameters used when sending voicemail notifications via email.
* doc.voicemail_settings.email_notifications[].attach_message (boolean) If true, when sending an email notification for voicemail, attach the audio file(s) to the email. Default: false.

        settings = await user.db.get 'voicemail_settings'
        return unless settings.email_notifications
        for email, params of settings.email_notifications
          p = send_email_notification message,
            email: email
            do_not_record: settings.do_not_record
            send_then_delete: settings.send_then_delete
            attach: params.attach_message
            language: settings.language
            user: user
            sender: sender
          await p.catch (error) ->
            debug "sendMail: #{inspect error}", message
        debug 'send_notification: done'

      cfg.notifiers.email ?= send_notification_to
      debug 'Configured.'
      return
