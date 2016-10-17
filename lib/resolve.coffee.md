URI DNS resolution and cache
============================

    seem = require 'seem'
    pkg = require '../package'
    @name = "#{pkg.name}:resolve"
    debug = (require 'debug') @name
    trace = (require 'debug') "#{@name}:trace"
    LRU = require 'lru-cache'

    Promise = require 'bluebird'
    dns = Promise.promisifyAll require 'dns'

    dns_cache = LRU
      max: 200
      maxAge: 10 * 60 * 1000

    module.exports = resolve = seem (uri) ->

      result = dns_cache.get uri
      return result if result?

      result = []

URI = username@host:port

      if m = uri.match /^([^@]+)@(^[@:]+):(\d+)$/
        name = m[2]
        port = m[3]
        trace 'resolve', {name,port}
        result.push {port,name}

URI = username@domain

      if m = uri.match /^([^@]+)@([^@:]+)$/
        domain = m[2]

        addresses = yield dns.resolveSrvAsync '_sip._udp.' + domain
        trace 'Addresses', addresses
        for address in addresses
          do (address) ->
            result.push address

      dns_cache.set uri, result
      result
