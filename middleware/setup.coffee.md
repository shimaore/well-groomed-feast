    pkg = require '../package.json'
    @name = "#{pkg.name}:middleware:setup"

    url = require 'url'
    qs = require 'querystring'

    @config = ->
      if @cfg.userdb_base_uri?
        {auth} = url.parse @cfg.userdb_base_uri
        if auth?
          @cfg.httapi_credentials ?= auth

    @web = ->
      @cfg.versions[pkg.name] = pkg.version

Use `mod_httpapi` to support URLs.

    @include = ->

      @voicemail_uri = (user,id,name,rev,simple) =>
        @prompt.uri 'user-db', user.database, id, name, rev, simple
