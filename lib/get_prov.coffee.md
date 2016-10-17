Provisioning cache
==================

    seem = require 'seem'
    LRU = require 'lru-cache'

    prov_cache = LRU
      max: 200
      maxAge: 20 * 1000

    module.exports = get_prov = seem (prov,key) ->

Use cache if available

      val = prov_cache.get key
      return val if val?

Use database otherwise

      val = yield prov
        .get key
        .catch (error) ->
          {}

      prov_cache.set key, val
      val
