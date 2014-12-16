(c) 2012 Stephane Alnet
Unlicensed in 2014

    mailer = require 'nodemailer'
    Milk = require 'milk'
    qs = require 'querystring'
    path = require 'path'
    Promise = require 'bluebird'
    smtpTransport = require 'nodemailer-smtp-transport'
    fs = Promise.promisifyAll require 'fs'
    winston = require 'winston'

    module.exports = (config) ->

      assert config.provisioning?, 'Missing `provisioning`'
      assert config.provisioning.local_couchdb_uri?, 'Missing `provisioning.local_couchdb_uri`'
      assert config.mailer?, 'Missing `mailer`'
      assert config.mailer.SMTP?, 'Missing `mailer.SMTP`'
      assert config.voicemail?, 'Missing `voicemail`'
      assert config.voicemail.userdb_base_uri, 'Missing `voicemail.userdb_base_uri`'
      assert config.host?, 'Missing `host`'

      provisioning_db = new PouchDB config.provisioning.local_couchdb_uri
      transporter = smtpTransport config.mailer.SMTP
      transport = mailer.createTransport transporter
      sendMail = Promise.promisify transport.sendMail
      logger = winston

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

        file_base = config.voicemail.file_base

        Promise.all (Object.keys default_templates).map (part) ->
          uri_name = [file_name, opts.language, part].join '.'

### Templates in the server configuration

          provisioning_db.getAttachment "host:#{config.host}", uri_name
          .catch (error) ->

### Templates stored on the local filesystem

            if file_base?
              fs.readFileAsync path.join(file_base,uri_name) , 'utf8'
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
                  content: user_db.request.get qs.escape(msg_id) + '/' + qs.escape(name)
                  contentType: data.content_type
                }

          sendMail email_options
          .catch (error) ->
            logger.error , "sendMail: #{error}", email_options
            throw error
          .then (info) ->

Delete record once all data has been emailed.

            if (opts.attach or opts.do_not_record) and opts.send_then_delete
              userdb.remove msg
          .catch (error) ->
            logger.error , "userdb.remove: #{error}", msg
            throw error

API wrapper
===========

      send_notification_to = (number,number_domain,msg_id) ->
        number_domain = number_domain or config.voicemail.number_domain ? 'local'
        user_db = null
        sender = null
        message = null

        provisioning_db.get "number:#{number}@#{number_domain}"
        .then (number_doc) ->
          if not number_doc.user_database? then return
          user_db = new PouchDB config.voicemail.userdb_base_uri + '/' + number_doc.user_database

          sender = number_doc.voicemail_sender ? config.voicemail.sender
        .then ->
          user_db.get msg_id
        .then (msg) ->
          message = msg
        .then ->
          user_db.get 'voicemail_settings'
        .then (settings) ->
          return unless settings.email_notifications
          for email, params of settings.email_notifications
            send_email_notification message,
              email: email
              do_not_record: settings.do_not_record
              send_then_delete: settings.send_then_delete
              attach: params.attach_message
              language: settings.language

      return send_notification_to
