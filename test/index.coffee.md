    describe 'The module', ->
      @timeout 3000
      it 'should load', ->
        process.env.CONFIG = './local/config.json'
        process.env.MODE = 'test'
        require '../index'
        return

    describe 'Middlewares', ->

      it 'email_notifier', ->
        m = require '../middleware/email_notifier'
        cfg =
          prov:true
        m.include.apply {cfg}

      it 'mwi_notifier', ->
        m = require '../middleware/mwi_notifier'
        cfg =
          prov:true
        m.include.apply {cfg}

      it 'setup', ->
        m = require '../middleware/setup'

      it 'voicemail', ->
        m = require '../middleware/voicemail'

    describe 'Classes', ->
      it 'User', ->
        m = require '../src/User'
      it 'Message', ->
        m = require '../src/Message'
      it 'Messaging', ->
        m = require '../src/Messaging'

    describe 'Other', ->
      it 'couchapp', ->
        m = require '../src/couchapp'
      it 'monitor', ->
        m = require '../monitor'
