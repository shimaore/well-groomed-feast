    {p_fun} = require 'coffeescript-helpers'
    seem = require 'seem'

    pkg = require './package'
    @name = "#{pkg.name}-#{pkg.version}-monitor"
    debug = (require 'debug') @name

    request = (require 'superagent-as-promised') require 'superagent'
    PouchDB = require 'pouchdb'
    uuid = require 'uuid'

    Nimble = require 'nimble-direction'

The couchapp used in the (local) provisioning database to monitor changes.

    id = "#{@name}-#{pkg.version}"
    couchapp =
      _id: "_design/#{id}"
      id: id
      views:
        userdb:
          map: p_fun (doc) ->
            if doc.user_database?
              emit doc.user_database, doc.name
      filters:
        numbers: p_fun (doc,req) ->
          return false unless doc.type is 'number'
          doc.default_voicemail_settings? or doc.user_database?

The couchapp inserted in the user's database, contains the views used by the voicemail application.

    user_app = require './src/couchapp'

Initial configuration
---------------------

    config = seem (cfg) ->

      yield Nimble cfg

Install the couchapp in the (local) provisioning database.

      yield cfg.push couchapp

Individual user database changes
--------------------------------

    monitored = seem (cfg,doc) ->

      {default_voicemail_settings,user_database} = doc

### Assign a user-database

If no user-database is specified (but a set of default voicemail settings is present), we create a new database.

      if not user_database?
        unless 'object' is typeof default_voicemail_settings
          debug "Invalid default_voicemail_settings: #{typeof default_voicemail_settings}"
          return
        user_database = "u#{uuid.v4()}"
        doc.user_database = user_database
        debug 'Setting user_database', doc
        yield cfg.master_push(doc).catch (error) ->
          return if error.status is 409
          debug "monitored: setting user_database: #{error}"

We exit at this point because updating the document will trigger a new `change` event.

        return

### Validate the user-database name

At this point we expect to have a valid user database name.

      if not user_database.match /^u[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
        debug 'Invalid db name', user_database
        cuddly.csr 'Invalid db name', user_database
        return

      target_db_uri = [cfg.userdb_base_uri,user_database].join '/'

### Create the database

Create / access the user database.

      target_db = new PouchDB target_db_uri
      debug 'Creating target database', target_db_uri
      yield target_db.info()

It's OK if the database already exists.

### Build access restrictions

Collect the list of users for this database

      debug 'Collect users', {user_database}
      {rows} = yield cfg.prov.query "#{couchapp.id}/userdb", key: user_database
      members_names = (row.value for row in rows)

Make sure the users can access it.

      debug 'Retrieve security object', {target_db_uri}
      security_uri = [target_db_uri,'_security'].join '/'
      {body} = yield request
        .get security_uri
        .accept 'json'

      security = body
      security.members ?= {}
      security.members.names = members_names
      security.members.roles = [ 'update:user_db:']

      debug 'Setting security', {security_uri,security}
      yield request
        .put security_uri
        .send security

### Limit number of documents revisions

Restrict number of available past revisions

      debug 'Restrict number of available past revisions'

      yield request
        .put [target_db_uri,'_revs_limit'].join '/'
        .send '10'

### Install the usercode

This is also done in `src/User`, but doing it here ensures the design document is available to outside applications (e.g. a web-based user panel).

      debug 'Insert user application'
      app = yield target_db
        .get user_app._id
        .catch -> {}
      app[k] = v for own k,v of user_app
      yield target_db
        .put app
        .catch -> true

### Install the voicemail settings

Create the voicemail settings record.

      VM_ID = 'voicemail_settings'

      vm_settings = yield target_db
        .get VM_ID
        .catch -> null

If the voicemail-settings document does not exist, create one based on the default voicemail settings specified.

      if not vm_settings?
        vm_settings = default_voicemail_settings ? {}
        vm_settings._id = VM_ID

If the voicemail-settings document exist, use the default voicemail settings for any non-existent field.

      else
        vm_settings[k] ?= v for own k,v of default_voicemail_settings ? {} when not k.match /^_/

      debug 'Update voicemail settings', vm_settings
      yield target_db
        .put vm_settings

      return

    module.exports = run = seem (cfg) ->
      return if process.env.MODE is 'test'

      debug 'Starting monitor.'

      yield config cfg

      cfg.prov.changes
        live: true
        filter: "#{couchapp.id}/numbers"
        include_docs: true
        since: 'now'
      .on 'change', ({doc}) ->
        monitored cfg, doc
      .on 'error', (err) ->
        run cfg

      return
