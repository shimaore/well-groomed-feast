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
        .catch (error) =>
          @gather_user attempts-1
        .then (number) =>
          @locate_user number, attempts-1

      locate_user: seem (number,attempts = 3) ->
        assert number?, 'locate_user: number must be defined'
        debug 'locate_user', number, attempts

        number_domain = null

Try to use the number-domain associated with the endpoint.

        endpoint = @ctx.req.header 'X-CCNQ3-Endpoint'

        @ctx.session.endpoint_data = {}
        if endpoint?
          {number_domain} = @ctx.session.endpoint_data =  yield @cfx.cfg.prov
            .get "endpoint:#{endpoint}"
            .catch (error) ->
              debug "Endpoint #{endpoint} not found, #{error}."
              {}

Fallback to the one specified in the headers.

        number_domain ?= @ctx.req.header 'X-CCNQ3-Number-Domain'

Fallback to the default one configured.

        if not number_domain?
          number_domain = @ctx.cfg.voicemail.number_domain ? 'local'
          cuddly.csr "No user_domain specified for #{number}, using configured #{number_domain} instead."

Attempt to locate the local-number record.

        user_id = "#{number}@#{number_domain}"

        debug 'locate_user >', user_id

        {user_database,_id} = @ctx.session.number_data = yield @ctx.cfg.prov
          .get "number:#{user_id}"
          .catch (error) ->
            debug "Number #{user_id} not found, #{error}."
            {}

If the record was not found, this might be due to the user mistyping their number when using `gather_user`, so give them another opportunity to do so.

        if not _id?
          return @gather_user attempts

If the record was found but no user-database is specified, either the line has no voicemail, or the record is incorrect. Either way, we can't proceed any further.

        if not user_database?
          debug "Customer #{user_id} has no user_database."
          cuddly.csr "Customer #{user_id} has no user_database."
          return @ctx.error 'MSI-42'

Now that we have a user/local-number document, let's locate the associated user database.
Note: `userdb_base_uri` must contain authentication elements (e.g. "voicemail" user+pass)

        db_uri = @ctx.cfg.userdb_base_uri + '/' + doc.user_database
        new User @ctx, user_id, doc.user_database, db_uri

    module.exports = Messaging
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Messaging"
    cuddly = (require 'cuddly') "#{pkg.name}:Messaging"
    assert = require 'assert'
    User = require './User'
