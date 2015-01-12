mockery = require 'mockery'
sinon = require 'sinon'
expect = require 'expect.js'
uuid = require 'node-uuid'
path = require 'path'
fs = require 'fs'

pass = -> undefined

describe 'bobbin', ->

	cluster_mock =
		isMaster: true
		setupMaster: (opts) ->
			expect(fs.existsSync opts.exec).to.be.ok()
		fork: ->
			on: pass
			send: pass

	bobbin = null

	before ->
		mockery.enable useCleanCache: true
		mockery.registerAllowable '../src/bobbin.coffee', true
		mockery.registerAllowables ['os', 'node-uuid', 'path']
		mockery.registerMock 'cluster', cluster_mock
		bobbin = require '../src/bobbin.coffee'

	describe '.create()', ->
		it 'should fail if not cluster.isMaster', ->
			cluster_mock.isMaster = false

			expect(-> bobbin.create()).to.throwError()
			
			cluster_mock.isMaster = true

		it 'should return a pool object', ->
			expect(bobbin.create()).to.be.an 'object'

		describe '[worker pool]', ->
			describe '.run()', ->
				it 'should be a function', ->
					pool = bobbin.create()

					expect(pool.run).to.be.a 'function'

				it 'should fail unless work param is a function', ->
					pool = bobbin.create()

					expect(->
						pool.run 1, (-> undefined)
					).to.throwError (e) -> expect(e).to.be.a TypeError

				it 'should fail unless callback param is a function', ->
					pool = bobbin.create()

					expect(->
						pool.run (-> undefined), 1
					).to.throwError (e) -> expect(e).to.be.a TypeError

				it 'should send work to another process via cluster', (done) ->
					data = [true, false, {foo: 1, bar: {baz: 'abc'}, quux: null}]
					work = (some, fake, params, callback) -> callback null, 'this should be serializable!'

					cluster_mock.fork = ->
						on: pass
						send: (msg) ->
							expect(msg.data).to.eql data
							expect(msg.work).to.equal work.toString()
							expect(msg.id).not.to.be undefined
							done()

					bobbin.create().run data..., work, -> undefined

				it 'should callback with the passed-in function', (done) ->
					handlers = {}
					id = undefined

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create().run pass, done

					handlers['message'] {id: id}

				it 'should callback with the parameters returned from the worker', (done) ->
					handlers = {}
					id = undefined
					params = ['foo', 'bar', 'baz', {quux: true, ziv: {a: 1, b:2}}]

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create().run pass, (data...) ->
						expect(data).to.eql params
						done()

					handlers['message'] {
						id: id
						callback_params: params
					}

	after ->
		mockery.disable()