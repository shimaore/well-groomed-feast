    describe 'Middlewares', ->
      m1 = require '../middleware/email_notifier'
      m2 = require '../middleware/mwi_notifier'
      m3 = require '../middleware/setup'
      m4 = require '../middleware/voicemail'

      it 'email_notifier', ->
        @timeout 4000
        cfg =
          provisioning:'http://127.0.0.1:5984/provisioning'
        await m1.include.apply {cfg}

      it 'mwi_notifier', ->
        @timeout 4000
        cfg =
          provisioning:'http://127.0.0.1:5984/provisioning'
        await m2.server_pre.call {cfg}, {cfg}
        await m2.include.call {cfg}, {cfg}
        await m2.end()

      it 'setup', ->
        cfg = {}
        await m3.config.call {cfg}, {cfg}

      it 'voicemail', ->
        await m4.include.call {}, {}

    describe 'Classes', ->
      it 'User', ->
        m = require '../src/User'
      it 'Message', ->
        m = require '../src/Message'
      it 'Messaging', ->
        m = require '../src/Messaging'
      it 'Formats', ->
        m = require '../src/Formats'

    describe 'Other', ->
      it 'couchapp', ->
        m = require '../src/couchapp'
      it 'monitor', ->
        m = require '../middleware/monitor'
