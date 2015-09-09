    class Messaging
      constructor: (@ctx) ->
        debug 'ctx', @ctx
        assert @ctx.cfg.prov?, 'Missing @ctx.cfg.prov'
        assert @ctx.cfg.userdb_base_uri?, 'Missing @ctx.cfg.userdb_base_uri'

Gather a customer phone number.

      gather_user: (attempts = 3) ->
        debug 'gather_user', {attempts}
        if attempts <= 0
          return @ctx.error()

        @ctx.get_number()
        .catch (error) =>
          @gather_user attempts-1
        .then (number) =>
          @locate_user number, attempts-1

      locate_user: (number,attempts = 3) ->
        assert number?, 'locate_user: number must be defined'
        debug 'locate_user', number, attempts

        number_domain = @ctx.req.header 'X-CCNQ3-Number-Domain'
        if not number_domain?
          number_domain = @ctx.cfg.voicemail.number_domain ? 'local'
          cuddly.csr "No user_domain specified, using configured #{number_domain} instead." # FIXME add number

        user_id = "#{number}@#{number_domain}"

        debug 'locate_user >', user_id

        @ctx.cfg.prov
        .get "number:#{user_id}"
        .then (doc) =>
          if not doc.user_database?
            debug "Customer #{user_id} has no user_database."
            cuddly.csr "Customer #{user_id} has no user_database."
            return @ctx.error 'MSI-42'

          # So we got a user document. Let's locate their user database.
          # userdb_base_uri must contain authentication elements (e.g. "voicemail" user+pass)
          db_uri = @ctx.cfg.userdb_base_uri + '/' + doc.user_database
          new User @ctx, user_id, doc.user_database, db_uri
        .catch (error) =>
          debug "Number #{user_id} not found (#{error}), trying again."
          @gather_user attempts

    module.exports = Messaging
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Messaging"
    cuddly = (require 'cuddly') "#{pkg.name}:Messaging"
    assert = require 'assert'
    User = require './User'
