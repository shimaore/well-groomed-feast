    class Messaging
      constructor: (@ctx) ->
        debug 'ctx', @ctx
        assert @ctx.cfg.prov?, 'Missing @ctx.cfg.prov'

Gather a customer phone number.

      gather_user: (attempts = 3) ->
        debug 'gather_user', {attempts}
        if attempts <= 0
          @ctx.goodbye()
          return

        @ctx.get_number()
        .catch (error) =>
          @gather_user attempts-1
          return
        .then (number) =>
          @locate_user number, attempts

      locate_user: (number,attempts = 3) ->
        debug 'locate_user', number, attempts

        if attempts <= 0
          @ctx.goodbye()
          return

        number_domain = @ctx.req.header 'X-CCNQ3-Number-Domain'
        if not number_domain?
          number_domain = @cfg.voicemail.number_domain ? 'local'
          cuddly.csr "No user_domain specified, using configured #{number_domain} instead." # FIXME add number

        user_id = "#{number}@#{number_domain}"

        debug 'locate_user >', user_id

        @ctx.cfg.prov
        .get "number:#{user_id}"
        .then (doc) =>
          if not doc.user_database?
            debug "Customer #{user_id} has no user_database."
            cuddly.csr "Customer #{user_id} has no user_database."
            @ctx.error 'MSI-42'
            return

          # So we got a user document. Let's locate their user database.
          # userdb_base_uri must contain authentication elements (e.g. "voicemail" user+pass)
          db_uri = @cfg.voicemail.userdb_base_uri + '/' + doc.user_database
          new User @ctx, db_uri, user_id
        .catch (error) =>
          debug "Number #{user_id} not found, trying again."
          @gather_user attempts-1

    module.exports = Messaging
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Messaging"
    cuddly = (require 'cuddly') "#{pkg.name}:Messaging"
    assert = require 'assert'
