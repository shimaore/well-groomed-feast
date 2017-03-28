    pkg = require '../package.json'
    @name = "#{pkg.name}:middleware:setup"
    debug = (require 'debug') @name

    url = require 'url'
    qs = require 'querystring'
    seem = require 'seem'

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
        db = qs.escape user.database
        id = qs.escape id
        rev = qs.escape rev ? 'current'
        name = qs.escape name
        @prompt.uri "/voicemail/#{db}/#{id}/#{rev}/#{name}", simple

Attachment upload/download
==========================

    @web = (ctx) ->

      @get '/voicemail/:db/:msg/:rev/:file', ->
        uri = "/#{qs @params.db}/#{qs @params.msg}/#{qs @params.file}"
        ctx.proxy_get @cfg.userdb_base_uri, uri

      @put '/voicemail/:db/:msg/:rev/:file', ->
        uri = "#{qs @params.db}/#{qs @params.msg}/#{qs @params.file}"
        ctx.proxy_put @cfg.userdb_base_uri, uri, @params.rev
