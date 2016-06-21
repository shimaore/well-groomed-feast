    seem = require 'seem'

    class Messaging
      constructor: (@ctx) ->
        debug 'ctx', @ctx
        assert @ctx.cfg.prov?, 'Missing @ctx.cfg.prov'
        assert @ctx.cfg.userdb_base_uri?, 'Missing @ctx.cfg.userdb_base_uri'

Gather a customer phone number and locate that record.

      gather_user: (attempts = 3) ->
        debug 'gather_user', {attempts}
        if attempts <= 0
          return @ctx.error()

        @ctx.get_number()
        .then (number) =>
          if number?
            @locate_user number, attempts-1
          else
            @gather_user attempts-1

      locate_user: seem (number,attempts = 3) ->
        assert number?, 'locate_user: number must be defined'
        debug 'locate_user', number, attempts

Locate endpoint-data (`User` will also need it, so store it in the session).
In most cases `session.endpoint` is already provided.

* session.endpoint_name Name of the endpoint used for locating the number-domain, set from hdr.X-CCNQ3-Endpoint.

        @ctx.session.endpoint_name ?= @ctx.req.header 'X-CCNQ3-Endpoint'

* session.endpoint Data of the endpoint used for locating the number-domain.

        @ctx.session.endpoint ?= yield @ctx.cfg.prov
          .get "endpoint:#{@ctx.session.endpoint_name}"
          .catch (error) =>
            debug "Endpoint #{@ctx.session.endpoint_name} not found, #{error}."
            null
          .then (data) ->
            if data?.disabled then {} else data

Internal consistency

        if @ctx.session.endpoint_name? and not @ctx.session.endpoint?
          cuddly.dev "Missing session.endpoint for #{@ctx.session.endpoint_name}"
          return @ctx.error 'MSI-48'

Number-domain selection
-----------------------

In most cases we will already have a proper `number_domain` selected in the session.

        number_domain = @ctx.session.number_domain ? null

Fallback to the number-domain associated with the endpoint, if any.

        number_domain ?= @ctx.session.endpoint?.number_domain

Fallback to the one specified in the headers.

* hdr.X-CCNQ3-Number-Domain In voicemail, used as fallback if the number domain could not be asserted from session.number_domain or session.endpoint.number_domain.

        number_domain ?= @ctx.req.header 'X-CCNQ3-Number-Domain'

Fallback to the default one configured.

* cfg.voicemail.number_domain The default number-domain used for voicemail, if none is found in session.number_domain, session.endpoint.number_domain, or hdr.X-CCNQ3-Number-Domain.

        if not number_domain?
          number_domain = @ctx.cfg.voicemail.number_domain ? 'local'
          cuddly.csr "No user_domain specified for #{number}, using configured #{number_domain} instead."

        @ctx.session.number_domain ?= number_domain

        {number_data,user} = yield @retrieve_number number

A missing `user` might be due to the user mistyping their number when using `gather_user`, so give them another opportunity to do so.

        if not user?
          return @gather_user attempts

Internal consistency

        assert number_data?, "Missing local number for #{user.id}"

        {user_database} = number_data

If the record was found but no user-database is specified, either the line has no voicemail, or the record is incorrect. Either way, we can't proceed any further.

        if not user_database?
          debug "Customer #{user.id} has no user_database."
          cuddly.csr "Customer #{user.id} has no user_database."
          return @ctx.error 'MSI-42'

        @ctx.session.number = number_data
        user

Retrieve user based on number and optional user-data
----------------------------------------------------

      retrieve_number: seem (number) ->

        number_domain = @ctx.session.number_domain

Pass through any translation that the application may suggest.

        if @ctx.translate_local_number?
          new_number = yield @ctx.translate_local_number number, number_domain
          number = new_number if new_number?

Attempt to locate the local-number record.

        user_id = "#{number}@#{number_domain}"

        debug 'retrieve_number >', user_id

* session.number Data record of the local number for which we are handling voicemail.
* doc.local_number.user_database Name of the user's database.
* session.number.user_database Name of the user's database, see doc.local_number.user_database

        number_data = yield @ctx.cfg.prov
          .get "number:#{user_id}"
          .catch (error) ->
            debug "number:#{user_id} not found, #{error}"
            cuddly.dev "number:#{user_id} not found, #{error}"
            {}
          .then (data) ->
            if data?.disabled then {} else data

Internal consistency

        unless number_data?._id?
          debug "No local number for #{user_id}"
          return {}

Use data from local-number

        {user_database} = number_data

        unless user_database?
          debug "Missing database for #{user_id}"
          return {number_data}

Now that we have a user/local-number document, let's locate the associated user database.
Note: `userdb_base_uri` must contain authentication elements (e.g. "voicemail" user+pass)

* cfg.userdb_base_uri The base URI concatenated with a doc.local_number.user_database name to access the user's database. It must contain any required authentication elements.

        db_uri = @ctx.cfg.userdb_base_uri + '/' + user_database
        user = new User @ctx, user_id, user_database, db_uri
        yield user.init_db()

        debug 'retrieve_number OK'
        {number_data,user}

    module.exports = Messaging
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Messaging"
    cuddly = (require 'cuddly') "#{pkg.name}:Messaging"
    assert = require 'assert'
    User = require './User'
