    describe 'The module', ->
      it 'should load', ->
        process.env.CONFIG = './local/config.json'
        process.env.MODE = 'test'
        require '../index'

    describe 'Middlewares', ->

      it 'email_notifier', ->
        m = require '../middleware/email_notifier'
        cfg =
          prov:true
        m.config.apply {cfg}

      it 'mwi_notifier', ->
        m = require '../middleware/mwi_notifier'
        cfg =
          prov:true
        m.config.apply {cfg}

      it 'setup', ->
        m = require '../middleware/setup'

      it 'voicemail', ->
        m = require '../middleware/voicemail'
