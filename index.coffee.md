Standard `tough-rate`
---------------------

    pkg = require './package.json'
    debug = (require 'debug') "#{pkg.name}:index"

    debug "Loading #{process.env.CONFIG}"
    cfg = require process.env.CONFIG

Default `use` list for tough-rate.

    debug 'cfg.use'
    cfg.use = [
      './middleware/setup'
      './middleware/email_notifier'
      './middleware/mwi_notifier'
      './middleware/voicemail'
    ]

    cfg.use = cfg.use.map (m) ->
      debug "Requiring #{m}"
      require m

Default FreeSwitch configuration

    debug 'Loading conf/freeswitch'
    cfg.freeswitch = require 'docker.tough-rate/conf/freeswitch'
    cfg.modules = [
      'mod_sndfile'
      'mod_tone_stream'
      'mod_httapi'
    ]
    cfg.phrases = [
      # require 'bumpy-lawyer/en'
      require 'bumpy-lawyer/fr'
    ]
    cfg.profile_module = require './conf/profile'

    if cfg.userdb_base_uri?
      {auth} = url.parse cfg.userdb_base_uri
      if auth?
        cfg.httapi_credentials ?= auth

    debug 'Loading thinkable-ducks'
    ducks = require 'thinkable-ducks'
    debug 'Starting'
    ducks cfg
    debug 'Ready'
