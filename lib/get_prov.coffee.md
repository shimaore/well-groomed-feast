Provisioning cache
==================

    LRU = require 'lru-cache'

    prov_cache = new LRU
      max: 200
      maxAge: 20 * 1000

    module.exports = get_prov = (prov,key) ->

Use cache if available

      val = prov_cache.get key
      return val if val?

Use database otherwise

      val = await prov
        .get key
        .catch (error) ->
          {}

      prov_cache.set key, val
      val
