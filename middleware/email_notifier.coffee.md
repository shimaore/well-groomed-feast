    mailer = require 'nodemailer'
    Milk = require 'milk'
    qs = require 'querystring'
    path = require 'path'
    Promise = require 'bluebird'
    smtpTransport = require 'nodemailer-smtp-transport'

    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:email_notifier"

    @name = "#{pkg.name}:email_notifier"
    @config = ->
      cfg = @cfg

      assert @cfg.prov, 'Missing prov'
      assert @cfg.mailer?, 'Missing `mailer`'
      assert @cfg.mailer.SMTP?, 'Missing `mailer.SMTP`'
      assert @cfg.voicemail?, 'Missing `voicemail`'
      assert @cfg.host?, 'Missing `host`'

      transporter = smtpTransport config.mailer.SMTP
      transport = mailer.createTransport transporter
      sendMail = Promise.promisify transport.sendMail


Template handling
=================

      send_email_notification = (msg,opts) ->
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

          cfg.prov.getAttachment "host:#{config.host}", uri_name
          .catch (error) ->
            null
          .then (data) ->
            template[part] = data ? default_templates[part]

Send email out
==============

        .then ->
          email_options =
            sender: sender ? opts.email
            to: opts.email
            subject: Milk.render template.subject, msg
            body: Milk.render template.body, msg
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
                  content: opts.user.db.request.get qs.escape(msg_id) + '/' + qs.escape(name)
                  contentType: data.content_type
                }

          sendMail email_options
          .catch (error) ->
            debug "sendMail: #{error}", email_options
            throw error
          .then (info) ->

Delete record once all data has been emailed.

            if (opts.attach or opts.do_not_record) and opts.send_then_delete
              userdb.remove msg
          .catch (error) ->
            debug "userdb.remove: #{error}", msg
            throw error

API wrapper
===========

      send_notification_to = (user,msg_id) ->
        sender = null
        message = null

        cfg.prov.get "number:#{id}"
        .then (number_doc) ->
          sender = number_doc.voicemail_sender ? config.voicemail.sender
        .then ->
          user.db.get msg_id
        .then (msg) ->
          message = msg
        .then ->
          user.db.get 'voicemail_settings'
        .then (settings) ->
          return unless settings.email_notifications
          for email, params of settings.email_notifications
            send_email_notification message,
              email: email
              do_not_record: settings.do_not_record
              send_then_delete: settings.send_then_delete
              attach: params.attach_message
              language: settings.language
              user: user

      @cfg.notifiers ?= []
      @cfg.notifiers.push send_notification_to
