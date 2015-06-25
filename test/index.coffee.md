    describe 'The module', ->
      it 'should load', ->
        process.env.CONFIG = './local/config.json'
        process.env.MODE = 'test'
        require '../index'
