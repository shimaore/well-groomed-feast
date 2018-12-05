URI DNS resolution and cache
============================

    pkg = require '../package'
    @name = "#{pkg.name}:resolve"
    debug = (require 'tangible') @name
    LRU = require 'lru-cache'

    dns = require 'dns'

    resolveSrvAsync = (name) -> new Promise (resolve,reject) ->
      dns.resolveSrv name, (err,res) -> if err then reject err else resolve res

    dns_cache = new LRU
      max: 200
      maxAge: 10 * 60 * 1000

    module.exports = resolve = (uri) ->

      result = dns_cache.get uri
      return result if result?

      result = []

URI = username@host:port

      if m = uri.match /^([^@]+)@(^[@:]+):(\d+)$/
        name = m[2]
        port = m[3]
        debug 'resolve', {name,port}
        result.push {port,name}

URI = username@domain

      if m = uri.match /^([^@]+)@([^@:]+)$/
        domain = m[2]

        addresses = await resolveSrvAsync '_sip._udp.' + domain
        debug 'Addresses', addresses
        addresses.forEach (address) ->
          result.push address

      dns_cache.set uri, result
      result
