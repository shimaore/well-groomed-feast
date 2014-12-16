The idea is to see whether we can do things like this:

    class Foo
      constructor: (@db) ->

      run: (call) ->
        result = null
        @db.get 'foo'
        .bind call
        .then (doc) ->
          result = doc
          call.command 'do_this'
        .then ->
          result

where the returned object (a Promise) is in the context of `call`.

    chai = require 'chai'
    chai.use require 'chai-as-promised'
    chai.should()

    Promise = require 'bluebird'

    describe 'When returning a bind promise', ->

First let's make sure we understand what 'bound' means.

      it 'a bound Promise should have a property on `this`', ->
        p = Promise.resolve true
        p = p.bind {name:'foo'}
        p.then ->
          this.should.have.property 'name', 'foo'

Then notice how the binding stays with the original Promise, not a returned one.

      it 'a returned bound Promise should have a property on `this`', ->
        p = Promise.resolve true
        p = p.bind {name:'bar'}
        p.then ->
          q = Promise.resolve false
          q = q.bind {name:'foo'}
        .then ->
          this.should.have.property 'name', 'bar'

Therefor we need to bind after we query.

    class DB
      get: (name) ->
        Promise.resolve {name}

    class Call
      constructor: ->
        @me = true
      command: (op) ->
        p = Promise.resolve true
        p = p.bind this
        p

    describe 'In a proper implementation', ->
      it 'the result should be in the context of that promise', ->
        db = new DB()
        foo = new Foo db
        call = new Call()
        call.should.have.property 'me', true
        res = foo.run call
        res.then (result) ->
          result.should.have.property 'name', 'foo'
          this.should.have.property 'me', true
