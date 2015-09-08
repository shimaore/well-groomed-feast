    {p_fun} = require 'coffeescript-helpers'
    pkg = require '../package.json'
    id = "#{pkg.name}-#{pkg.version}-voicemail"

    ddoc =
      _id: "_design/#{id}"
      id: id
      language: 'javascript'
      views: {}

    module.exports = ddoc

Note: These only list _messages_, i.e. documents with actual audio content.

    ddoc.views.new_messages =
      map: p_fun (doc) ->

        if doc.type? and doc.type is 'voicemail' and doc.box? and doc.box is 'new' and doc._attachments?
          emit doc._id, null

    ddoc.views.saved_messages =
      map: p_fun (doc) ->

        if doc.type? and doc.type is 'voicemail' and doc.box? and doc.box is 'saved' and doc._attachments?
          emit doc._id, null

    ddoc.views.no_messages =
      map: p_fun (doc) ->

        if doc.type? and doc.type is 'voicemail' and (not doc.box? or not doc._attachments?)
          emit doc._id, null
