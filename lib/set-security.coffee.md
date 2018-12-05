Set Security
============

    name = "well-groomed-feast:lib:set-security"
    debug = (require 'tangible') name

    module.exports = set_security = (db,users = []) ->
      return unless typeof db.uri is 'string'
      return unless db.uri.match ///
        / u
        [a-f\d]{8} -
        [a-f\d]{4} -
        [a-f\d]{4} -
        [a-f\d]{4} -
        [a-f\d]{12}
        $ ///

Set the proper security document.

      uri = new URL '_security', db.uri+'/'

      db.agent
        .put uri.toString()
        .send
          members:
            names: users
            roles: [
              "user_database:#{db}"
              'update:user_db:'
            ]
          admins:
            names: []
            roles: [
              '_admin'
            ]
