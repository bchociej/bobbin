mockery = require 'mockery'
sinon = require 'sinon'
expect = require 'expect.js'
uuid = require 'node-uuid'
path = require 'path'
fs = require 'fs'
num_cpus = require('os').cpus().length

pass = -> undefined
reflex = (cb) -> cb()
slow_reflex = (cb) -> setTimeout cb, 10

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

		it 'should create num_cpus processes by default', (done) ->
			handlers = {}
			id = undefined

			i = 0

			cluster_mock.fork = ->
				if ++i > num_cpus
					expect.fail 'bobbin created more processes than cpus'

				send: pass
				on: pass

			bobbin.create()

			# to cleanly end the test
			did = false

			cluster_mock.fork = ->
				unless did
					expect(i).to.eql num_cpus
					done()
					did = true

				send: pass
				on: pass

			bobbin.create()

		it 'should create N processes for N >= 1', (done) ->
			handlers = {}
			id = undefined

			i = 0

			cluster_mock.fork = ->
				if ++i > 10
					expect.fail 'bobbin created more processes than cpus'

				send: pass
				on: pass

			bobbin.create(10)

			# to cleanly end the test
			did = false

			cluster_mock.fork = ->
				unless did
					expect(i).to.eql 10
					did = true

				send: pass
				on: pass

			bobbin.create(1)

			i = 0

			cluster_mock.fork = ->
				if ++i > 2
					expect.fail 'bobbin created more processes than cpus'

				send: pass
				on: pass

			bobbin.create(2)

			# to cleanly end the test
			did = false

			cluster_mock.fork = ->
				unless did
					expect(i).to.eql 2
					done()
					did = true

				send: pass
				on: pass

			bobbin.create(1)

		it 'should create num_cpus processes when N < 1', (done) ->
			handlers = {}
			id = undefined

			i = 0

			cluster_mock.fork = ->
				if ++i > num_cpus
					expect.fail 'bobbin created more processes than cpus'

				send: pass
				on: pass

			bobbin.create(0.9)

			# to cleanly end the test
			did = false

			cluster_mock.fork = ->
				unless did
					expect(i).to.eql num_cpus
					done()
					did = true

				send: pass
				on: pass

			bobbin.create()

		it 'should create num_cpus processes when N invalid', (done) ->
			handlers = {}
			id = undefined

			i = 0

			cluster_mock.fork = ->
				if ++i > num_cpus
					expect.fail 'bobbin created more processes than cpus'

				send: pass
				on: pass

			bobbin.create('pickles')

			# to cleanly end the test
			did = false

			cluster_mock.fork = ->
				unless did
					expect(i).to.eql num_cpus
					done()
					did = true

				send: pass
				on: pass

			bobbin.create()

		it 'should return a pool object (run, kill, path)', ->
			pool = bobbin.create()
			expect(pool).to.be.an 'object'
			expect(pool.run).to.be.a 'function'
			expect(pool.kill).to.be.a 'function'
			expect(pool.path).to.be.a 'function'

		describe '[worker pool]', ->

			describe '.run()', ->

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

					handlers['message'] {type: 'result', contents: {id: id}}

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
						type: 'result'
						contents: {
							id: id
							callback_params: params
						}
					}

				it 'should apply a WorkerError to the callback when a worker throws an Error', (done) ->
					handlers = {}
					id = undefined
					params = ['foo', 'bar', 'baz', {quux: true, ziv: {a: 1, b:2}}]

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create().run pass, (err, result) ->
						expect(err).to.be.a bobbin.WorkerError
						expect(err.message).to.be 'what up'
						expect(err.name).to.be 'Error'
						expect(result).to.be undefined
						done()

					handlers['message'] {
						type: 'exception'
						contents: {
							id: id
							is_error: true
							error: {
								type: 'Error'
								parameters: {
									name: 'Error'
									message: 'what up'
								}
							}
						}
					}

				it 'should apply a thrown non-Error exception to the callback just like an error', (done) ->
					handlers = {}
					id = undefined
					params = ['foo', 'bar', 'baz', {quux: true, ziv: {a: 1, b:2}}]

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create().run pass, (err, result) ->
						expect(err).not.to.be.an Error
						expect(err).to.be 'bad thing'
						expect(result).to.be undefined
						done()

					handlers['message'] {
						type: 'exception'
						contents: {
							id: id
							is_error: false
							exception: 'bad thing'
						}
					}

				it 'should prefer idle workers', (done) ->
					workers = []
					count = 0

					cluster_mock.fork = ->
						handlers = {}
						id = undefined

						# extra handler and id accessors for twiddling with stuff later on
						workers.push
							send: (msg) ->
								id = msg.id
								count++

							on: (ev, handler) ->
								handlers[ev] = handler

							handler: (ev) ->
								handlers[ev]

							id: -> id

						workers[workers.length - 1]


					# create 30 workers and give them each 2 jobs that will never finish
					pool = bobbin.create(30)
					expect(workers.length).to.be 30
					pool.run(pass, pass) for i in [1..60]
					expect(count).to.be 60



					# fail if busy workers get work
					busyfail = (i) ->
						-> expect().fail "sent work to busy worker #{i} when there was an idle worker available!"

					for i in [0...30]
						workers[i].send = busyfail(i)



					# emulate 'empty' message for worker 14
					workers[14].handler('message')({
						type: 'result'
						contents:
							id: workers[14].id()
							callback_params: [null, 'foo']
					}) for i in [1..2]
					workers[14].handler('message')({type: 'empty'})

					# once the #14 test passes, do it again with 22 and 6 for good measure
					workers[14].send = ->
						workers[22].handler('message')({
							type: 'result'
							contents:
								id: workers[22].id()
								callback_params: [null, 'foo']
						}) for i in [1..2]
						workers[22].handler('message')({type: 'empty'})

						workers[14].send = busyfail(14)
						workers[22].send = ->
							workers[6].handler('message')({
								type: 'result'
								contents:
									id: workers[6].id()
									callback_params: [null, 'foo']
							}) for i in [1..2]
							workers[6].handler('message')({type: 'empty'})

							workers[22].send = busyfail(22)
							workers[6].send = ->
								# if we got here without a busyfail going off, things worked correctly
								done()

							pool.run pass, pass

						pool.run pass, pass

					pool.run pass, pass

				it 'should pass module.parent.filename to worker'


			describe '.kill()', ->

				it 'should kill all workers immediately when called with no timeout', ->
					spy = sinon.spy()

					cluster_mock.fork = ->
						killed = false

						send: pass
						on: pass
						kill: ->
							unless killed
								killed = true
								spy()


					pool = bobbin.create(10)
					pool.kill()

					expect(spy.callCount).to.eql 10

				it 'should kill workers after work finishes if called with sufficient timeout', (done) ->
					work_done_count = 0
					killed_count = 0
					handlers = {}

					inc = ->
						if ++killed_count is 10
							expect(work_done_count).to.eql 20

					cluster_mock.fork = ->
						killed = false

						send: (msg) ->
							setTimeout (->
								handlers['message'] {
									type: 'result'
									contents:
										id: msg.id
										callback_params: []
								}
							), 10
						on: (ev, handler) ->
							handlers[ev] = handler
						kill: ->
							unless killed
								killed = true
								inc()

					pool = bobbin.create(10)
					
					inc_done = ->
						if ++work_done_count >= 20
							done()

					pool.run((-> 'dummy function -- this test ignores this function'), inc_done) for i in [1..20]
					
					pool.kill(1500)

				it 'should kill workers prematurely if called with small timeout', (done) ->
					work_done_count = 0
					killed_count = 0
					handlers = {}

					inc = ->
						if ++killed_count is 10
							expect(work_done_count).to.eql 0
							done()

					cluster_mock.fork = ->
						killed = false

						send: (msg) ->
							setTimeout (->
								handlers['message'] {
									type: 'result'
									contents:
										id: msg.id
										callback_params: []
								}
							), 1000
						on: (ev, handler) ->
							handlers[ev] = handler
						kill: ->
							unless killed
								killed = true
								inc()

					pool = bobbin.create(10)
					
					inc_done = ->
						if ++work_done_count >= 1
							expect().fail('should not have run inc_done')

					pool.run((-> 'dummy function -- this test ignores this function'), inc_done) for i in [1..20]
					
					pool.kill(1)

				it 'should raise an error if new work is submitted after kill()', ->
					pool = bobbin.create()
					pool.kill()

					expect(-> pool.run reflex, pass).to.throwError /kill has been called/

				it 'should raise an error if a bad timeout value is passed', ->
					pool = bobbin.create()
					expect(-> pool.kill(-1)).to.throwError /non\-negative/
					expect(-> pool.kill(false)).to.throwError /non\-negative/


			describe '.path()', ->

				it 'should return a pool object (run, kill, path) when called with a valid directory'

				it 'should throw an error when its argument is not a string'

				it 'should throw an error when the directory argument is not accessible'

				it 'should throw an error when the directory argument is not a directory'

				it 'should cause the given directory name to be passed to workers'

	after ->
		mockery.disable()