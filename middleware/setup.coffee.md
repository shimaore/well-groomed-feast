    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:setup"

    Promise = require 'bluebird'
    nimble = require 'nimble-direction'

    @name = "#{pkg.name}/middleware/setup"
    @web = ->
      @cfg.versions[pkg.name] = pkg.version

    class ChoiceError extends Error
      choice: true

    @config = ->
      cfg = @cfg
      debug "Configuring #{pkg.name} version #{pkg.version}.", cfg
      nimble cfg
      .then ->
        assert cfg.prov?, 'Nimble did not inject cfg.prov'
        debug "Configured."

Use `mod_httpapi` to support URLs.

    @include = (ctx) ->


`record`
========

Record using the given file or uri.

https://wiki.freeswitch.org/wiki/Misc._Dialplan_Tools_record

      ctx.record = (file,time_limit = 300) ->
        debug "record", {file,time_limit}
        silence_thresh = 20
        silence_hits = 3
        ctx.call.command 'record', [
          file
          time_limit
          silence_thresh
          silence_hits
        ].join ' '

`play_and_get_digits`
=====================

Simple wrapper for FreeSwitch's `play_and_get_digits`.

Required options:
- `min`
- `max`
- `timeout`
- `file`
- `var_name`
- `regexp`
- `digit_timeout`


https://wiki.freeswitch.org/wiki/Misc._Dialplan_Tools_play_and_get_digits

      ctx.play_and_get_digits = (o) ->
        debug 'play_and_get_digits', o
        ctx.action 'play_and_get_digits', [
          o.min
          o.max
          o.tries ? 1
          o.timeout
          o.terminators ? '#'
          o.file
          o.invalid_file ? 'silence_stream://250'
          o.var_name
          o.regexp
          o.digit_timeout
          o.transfer_on_failure ? ''
        ].join ' '

`play`
======

Play a file and optionnally record a single digit.
Promise resolves into the selected digit or rejects.

      ctx.play = (file,o={}) ->
        o.file = file
        o.min ?= 1
        o.max ?= 1
        o.timeout ?= 1000
        o.var_name ?= 'choice'
        o.regexp ?= '\\d'
        o.digit_timeout ?= 1000
        ctx.play_and_get_digits o
        .then ({body}) ->
          name = "variable_#{o.var_name}"
          debug "Got #{body[name]} for #{name}"
          body[name] ? Promise.reject new ChoiceError "Missing #{o.var_name}"

`get_choice`
========

Play a file and optionnaly record a single digit.
Promise resolves into the selected digit or rejects.

      ctx.get_choice = (file,o={}) ->
        o.timeout ?= 15000
        o.digit_timeout ?= 3000
        ctx.play file, o

`get_number`
============

Asks for a number.
Promise resolves into the number or rejects.

      ctx.get_number = (o={}) ->
        o.file ?= 'phrase:voicemail_enter_id:#'
        o.invalid_file ?= "phrase:'voicemail_fail_auth'"
        o.min ?= 1
        o.max ?= 16
        o.var_name ?= 'number'
        o.regexp ?= '\\d+'
        o.digit_timeout ?= 3000
        ctx.get_choice o.file, o

`get_pin`
=========

Asks for a PIN.
Promise resolves into the PIN or rejects.

      ctx.get_pin = (o={}) ->
        o.file ?= 'phrase:voicemail_enter_pass:#'
        o.min ?= 4
        o.max ?= 16
        o.var_name ?= 'pin'
        ctx.get_number o

`get_new_pin`
=============

Asks for a new PIN.
Promise resolves into the new PIN or rejects.

      ctx.get_new_pin = (o={}) ->
        o.var_name ?= 'new_pin'
        o.invalid_file = 'silence_stream://250'
        ctx.get_pin o

      ctx.goodbye = ->
        debug 'goodbye'
        ctx.action 'phrase', 'voicemail_goodbye'
        .then ->
          ctx.action 'hangup'
        .catch (error) ->
          debug "goodbye: #{error}"

      ctx.error = (id) ->
        debug 'error', {id}
        Promise.resolve true
        .then ->
          ctx.action 'phrase', "spell,#{id}" if id?
        .then ->
          ctx.goodbye()
        .then ->
          Promise.reject new Error "error #{id}"

      nimble ctx.cfg