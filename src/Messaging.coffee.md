    class Messaging
      constructor: (@ctx,@config) ->

      goodbye: ->
        @ctx.action 'phrase', 'voicemail_goodbye'
        .then =>
          @ctx.hangup()

      error: ->
        # FIXME
        @goodbye()
        # play ... "An error occurred. Please hang up and try again. If the problem repeats, ..."

Gather a customer phone number.

      gather_user: (attempts = 3) ->
        debug 'gather_user', {attempts}
        @ctx.get_number()
        .then (number) =>
           @locate_user number, attempts-1

      locate_user: (number,attempts = 3) ->
        debug 'locate_user', number, attempts

        if attempts <= 0
          return @goodbye()

        number_domain = @ctx.req.header 'X-CCNQ3-Number-Domain'
        if not number_domain?
          number_domain = @cfg.voicemail.number_domain ? 'local'
          cuddly.csr "No user_domain specified, using configured #{number_domain} instead." # FIXME add number

        user_id = "#{number}@#{number_domain}"

        debug 'locate_user > ', user_id

Confirm `@prov` is available?
Yes it is, middlewate/setup uses nimble-direction.

        @prov
        .get "number:#{user_id}"
        .then (doc) =>
          if not doc.user_database?
            cuddly.csr "Customer #{user_id} has no user_database."
            return @error()

          # So we got a user document. Let's locate their user database.
          # userdb_base_uri must contain authentication elements (e.g. "voicemail" user+pass)
          db_uri = @cfg.voicemail.userdb_base_uri + '/' + doc.user_database
          new User @ctx, db_uri, user_id
        .catch (error) ->
          cuddly.csr "Number #{user_id} not found, trying again."
          @error()

    module.exports = Messaging
    pkg = require '../package.json'
    debug = (require 'debug') "#{pkg.name}:Messaging"
