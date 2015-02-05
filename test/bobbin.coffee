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

	cluster_mock = undefined

	fresh_cluster_mock = ->
		o = {}
		
		o.isMaster = true
		
		o.setupMaster = (opts) ->
			expect(fs.existsSync opts.exec).to.be.ok()

		o.fork = ->
			on: pass
			send: pass

		return o

	bobbin = null

	before ->
		mockery.enable useCleanCache: true
		
		mockery.registerAllowable '../src/bobbin.coffee', true
		mockery.registerAllowables ['os', 'node-uuid', 'path', 'fs']

		cluster_mock = fresh_cluster_mock()
		mockery.registerMock 'cluster', cluster_mock

		bobbin = require '../src/bobbin.coffee'

	describe '.create()', ->

		it 'should fail if not cluster.isMaster', (done) ->
			cluster_mock.isMaster = false

			bobbin.create (err, pool) ->
				expect(err).to.be.an Error
				expect(pool).to.eql undefined
				done()

			cluster_mock.isMaster = true

		it 'should create num_cpus processes by default', (done) ->
			i = 0

			cluster_mock.fork = ->
				if ++i > num_cpus
					expect().fail 'bobbin created more processes than cpus'

				send: pass
				on: pass

			bobbin.create (err, pool) ->
				expect(err).to.be null
				expect(i).to.be num_cpus
				done()

		it 'should create N processes for num_workers = N >= 1', (done) ->
			i = 0

			cluster_mock.fork = ->
				if ++i > 10
					expect().fail 'bobbin created more processes than requested'

				send: pass
				on: pass

			bobbin.create 10, (err, pool) ->
				expect(err).to.be null
				expect(i).to.be 10

				i = 0

				cluster_mock.fork = ->
					if ++i > 3
						expect().fail 'bobbin created more processes than requested'

					send: pass
					on: pass

				bobbin.create 3, (err, pool) ->
					expect(err).to.be null
					expect(i).to.be 3

					i = 0

					cluster_mock.fork = ->
						if ++i > 1024
							expect().fail 'bobbin created more processes than requested'

						send: pass
						on: pass

					bobbin.create 1024, (err, pool) ->
						expect(err).to.be null
						expect(i).to.be 1024

						done()

		it 'should fail when num_workers < 1', (done) ->
			cluster_mock.fork = ->
				send: pass
				on: pass

			bobbin.create 0.9, (err, pool) ->
				expect(err).to.be.an Error
				expect(pool).to.eql undefined
				done()


		it 'should fail when num_workers isNaN', (done) ->
			cluster_mock.fork = ->
				send: pass
				on: pass

			bobbin.create (0/0), (err, pool) ->
				expect(err).to.be.an Error
				expect(pool).to.eql undefined
				done()

		it 'should fail when num_workers is gigantic (N > 1024)', (done) ->
			cluster_mock.fork = ->
				send: pass
				on: pass

			bobbin.create 1025, (err, pool) ->
				expect(err).to.be.an Error
				expect(pool).to.eql undefined
				done()

		it 'should return a pool object (run, kill, path)', (done) ->
			bobbin.create (err, pool) ->
				expect(pool).to.be.an 'object'
				expect(pool.run).to.be.a 'function'
				expect(pool.kill).to.be.a 'function'
				expect(pool.path).to.be.a 'function'
				done()

		describe '[worker pool]', ->

			describe '.run()', ->

				it 'should fail unless work param is a function', (done) ->
					bobbin.create (err, pool) ->
						pool.run 'not a function', (err, result) ->
							expect(err).to.be.a bobbin.BobbinError
							expect(result).to.eql undefined
							done()

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

					bobbin.create (err, pool) -> pool.run(data..., work, -> undefined)

				it 'should callback with the passed-in function', (done) ->
					handlers = {}
					id = undefined

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create (err, pool) ->
						pool.run pass, done
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

					bobbin.create (err, pool) ->
						pool.run pass, (data...) ->
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

					bobbin.create (err, pool) ->
						pool.run pass, (err, result) ->
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

					bobbin.create (err, pool) ->
						pool.run pass, (err, result) ->
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
					pool = bobbin.create 30, (err, pool) ->
						expect(workers.length).to.be 30
						pool.run(pass, pass) for i in [1..60]

						process.nextTick ->
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

				it 'should pass parent module dirname to worker', (done) ->
					handlers = {}
					id = undefined

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
							expect(msg.dirname).to.be path.dirname(module.filename)
							done()
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create (err, pool) ->
						pool.run pass, pass

				it 'should pass the specified dirname to worker when called with a dirname', (done) ->
					handlers = {}
					id = undefined

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
							expect(msg.dirname).to.be __dirname
							done()
						on: (ev, handler) ->
							handlers[ev] = handler

					bobbin.create __dirname, (err, pool) ->
						pool.run pass, pass


			describe '.kill()', ->

				it 'should kill all workers immediately when called with no timeout', (done) ->
					spy = sinon.spy()

					cluster_mock.fork = ->
						killed = false

						send: pass
						on: pass
						kill: ->
							unless killed
								killed = true
								spy()

					pool = bobbin.create 10, (err, pool) ->
						pool.kill (err) ->
							expect(err).to.eql undefined
							expect(spy.callCount).to.eql 10
							done()

				it 'should kill workers after work finishes if called with sufficient timeout', (done) ->
					work_done_count = 0
					killed_count = 0
					handlers = {}

					inc = ->
						expect(++killed_count).to.be.below 11

						if killed_count is 10
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

					bobbin.create 10, (err, pool) ->
						inc_done = (err) ->
							expect(err).to.eql undefined
							expect(++work_done_count).to.be.below 21

						pool.run((-> 'dummy function -- this test ignores this function'), inc_done) for i in [1..20]
						
						pool.kill 100, (err) ->
							expect(work_done_count).to.be 20
							expect(killed_count).to.be 10
							done()

				it 'should kill workers prematurely if called with small timeout', (done) ->
					work_done_count = 0
					killed_count = 0
					handlers = {}

					inc = ->
						expect(++killed_count).to.be.below 11
						expect(work_done_count).to.be 0

					cluster_mock.fork = ->
						killed = false
						timeout = undefined

						send: (msg) ->
							timeout = setTimeout (->
								if not killed then handlers['message'] {
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
								clearTimeout timeout
								inc()

					bobbin.create 10, (err, pool) ->
						work_done = (err) ->
							expect(err).to.be.a bobbin.BobbinError
							expect(err.message).to.match /no new work/

							unless err?
								expect(++work_done_count).to.be 0

						pool.run((-> 'dummy function -- this test ignores this function'), work_done) for i in [1..20]
						
						process.nextTick ->
							pool.kill 1, (err) ->
								expect(work_done_count).to.be 0
								expect(killed_count).to.be 10
								done()

				it 'should raise an error if new work is submitted after kill()', (done) ->
					cluster_mock.fork = ->
						send: pass
						on: pass
						kill: pass

					bobbin.create (err, pool) ->
						pool.kill() # kill is immediate if 0 or no timeout
						pool.run reflex, (err, result) ->
							expect(err).to.be.a bobbin.BobbinError
							expect(result).to.eql undefined
							expect(err.message).to.match /no new work/
							done()

				it 'should raise an error if a bad timeout value is passed', ->
					cluster_mock.fork = ->
						send: pass
						on: pass
						kill: pass

					bobbin.create (err, pool) ->
						pool.kill -1, (err) ->
							expect(err).to.be.a bobbin.BobbinError
							expect(err.message).to.match /non\-negative/
						
							pool.kill false, (err) ->
								expect(err).to.be.a bobbin.BobbinError
								expect(err.message).to.match /non\-negative number/


			describe '.path()', ->

				it 'should return a pool object (run, kill, path) when called with a valid directory', (done) ->
					cluster_mock.fork = ->
						send: pass
						on: pass
						kill: pass

					bobbin.create (err, pool) ->
						expect(err).to.eql null

						pool.path './', (err, pool) ->
							expect(err).to.eql null
							expect(pool).to.be.an 'object'
							expect(pool.run).to.be.a 'function'
							expect(pool.kill).to.be.a 'function'
							expect(pool.path).to.be.a 'function'
							done()

				it 'should throw an error when its argument is not a string', (done) ->
					cluster_mock.fork = ->
						send: pass
						on: pass
						kill: pass

					bobbin.create (err, pool) ->
						expect(err).to.eql null

						pool.path 4, (err, pool) ->
							expect(err).to.be.a TypeError
							expect(err.message).to.match /string/
							expect(pool).to.be undefined
							done()

				it 'should throw an error when the directory argument is not accessible', (done) ->
					cluster_mock.fork = ->
						send: pass
						on: pass
						kill: pass

					bobbin.create (err, pool) ->
						expect(err).to.eql null

						pool.path '/not/a/real/path/', (err, pool) ->
							expect(err).to.be.an Error
							expect(err.message).to.match /ENOENT/
							expect(pool).to.be undefined
							done()
					

				it 'should throw an error when the directory argument is not a directory', (done) ->
					cluster_mock.fork = ->
						send: pass
						on: pass
						kill: pass

					bobbin.create (err, pool) ->
						expect(err).to.eql null

						pool.path module.filename, (err, pool) ->
							expect(err).to.be.an Error
							expect(err.message).to.match /not a directory/
							expect(pool).to.be undefined
							done()

				it 'should cause the given directory name to be passed to workers', (done) ->
					handlers = {}
					id = undefined

					cluster_mock.fork = ->
						send: (msg) ->
							id = msg.id
							expect(msg.dirname).to.be __dirname
							done()
						on: (ev, handler) ->
							handlers[ev] = handler
						kill: pass

					bobbin.create (err, pool) ->
						expect(err).to.eql null

						pool.path __dirname, (err, pool) ->
							expect(err).to.eql null
							expect(pool).to.be.an 'object'

						pool.run pass, pass

	after ->
		mockery.disable()