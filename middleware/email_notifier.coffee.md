    mailer = require 'nodemailer'
    Milk = require 'milk'
    qs = require 'querystring'
    path = require 'path'
    Promise = require 'bluebird'
    seem = require 'seem'
    smtpTransport = require 'nodemailer-smtp-transport'

    pkg = require '../package.json'
    @name = "#{pkg.name}:email_notifier"
    debug = (require 'debug') @name
    assert = require 'assert'

    @include = ->
      cfg = @cfg
      cfg.notifiers ?= {}
      return if cfg.notifiers.email?

      assert cfg.prov, 'Missing prov'

      unless cfg.mailer?.SMTP?
        debug 'Missing `mailer.SMTP`'
        return
      unless cfg.voicemail?.sender?
        debug 'Missing `voicemail.sender`'
        return
      unless cfg.host?
        debug 'Missing `host`'
        return

      transporter = smtpTransport cfg.mailer.SMTP
      transport = mailer.createTransport transporter
      sendMail = Promise.promisify transport.sendMail


Template handling
=================

      send_email_notification = (msg,opts) ->
        debug 'send_email_notification', {msg,opts}
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

        Promise.all (Object.keys default_templates).map (part) ->
          uri_name = [file_name, opts.language, part].join '.'

### Templates in the server configuration

          cfg.prov.getAttachment "host:#{cfg.host}", uri_name
          .catch (error) ->
            null
          .then (data) ->
            template[part] = data ? default_templates[part]

Send email out
==============

        .then ->
          debug 'Ready to send.'
          email_options =
            from: sender ? opts.email
            to: opts.email
            subject: Milk.render template.subject, msg
            text: Milk.render template.body, msg
            html: Milk.render template.html, msg
            attachments: []

          if opts.attach and msg._attachments

Alternatively, enumerate the part#{n}.#{extension} files? (FIXME?)

            for name, data of msg._attachments
              do (name,data) ->

`data` fields might be: `content_type`, `revpos`, `digest`, `length`, `stub`:boolean

FIXME: Migrate to new `node_mailer` conventions.

                email_options.attachments.push {
                  filename: name
                  path: ctx.uri opts.user, msg._id, name, null, true
                  contentType: data.content_type
                }

          debug 'sendMail', email_options
          sendMail.call transport, email_options
          .then (info) ->
            debug 'sendMail', info

Delete record once all data has been emailed.

            if (opts.attach or opts.do_not_record) and opts.send_then_delete
              user.db.remove msg
          .catch (error) ->
            debug "sendMail: #{error}", msg

API wrapper
===========

      send_notification_to = seem (user,msg_id) ->
        debug 'send_notification_to', {user,msg_id}

We can only send emails about a specific message.

        return unless msg_id?

        number_doc = yield cfg.prov.get "number:#{user.id}"
        return if number_doc.disabled
        sender = number_doc.voicemail_sender ? cfg.voicemail.sender
        message = yield user.db.get msg_id

We should only email about new messages.

        return unless message.box is 'new'

        settings = yield user.db.get 'voicemail_settings'
        return unless settings.email_notifications
        notifications = for email, params of settings.email_notifications
          send_email_notification message,
            email: email
            do_not_record: settings.do_not_record
            send_then_delete: settings.send_then_delete
            attach: params.attach_message
            language: settings.language
            user: user
        yield Promise.all notifications
        debug 'send_notification: done'

      cfg.notifiers.email ?= send_notification_to
      debug 'Configured.'
