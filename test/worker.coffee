mockery = require 'mockery'
expect = require 'expect.js'

describe 'worker', ->

	reflex = ((cb) -> cb()).toString()

	slow_reflex = ((cb) ->
		setTimeout cb, 10
	).toString()

	pass = -> undefined

	cluster_mock =
		isMaster: false
		isWorker: true

	handlers = {}

	process_mock = (send_handler) ->
		on: (ev, handler) ->
			handlers[ev] = handler
		send: send_handler

	worker = null

	before ->
		mockery.enable useCleanCache: true, warnOnReplace: false
		mockery.registerAllowable '../src/worker.coffee', true
		mockery.registerMock 'cluster', cluster_mock
		worker = require '../src/worker.coffee'

	it 'should fail unless cluster.isWorker', ->
		cluster_mock.isWorker = false
		expect(-> worker()).to.throwError()
		cluster_mock.isWorker = true

	it 'should run the work function', (done) ->
		worker(process_mock -> undefined)

		run_tester = (what) ->
			expect(what).to.eql 'hello world'
			done()

		handlers['message'] {
			id: 'blah'
			data: [run_tester]
			work: ((rt, cb) ->
				rt 'hello world'
				cb()
			).toString()
		}

	it 'should call back with the task id', (done) ->
		id = 'fizzbuzzwhatup'

		worker(process_mock (msg) ->
			if msg.type is 'result'
				expect(msg.contents.id).to.eql id
				done()
		)

		handlers['message'] {
			id: id
			data: []
			work: reflex
		}

	it 'should notify the master when its function queue is empty', (done) ->
		result_count = 0
		id = 'blah'

		worker(process_mock (msg) ->
			if msg.type is 'empty'
				expect(result_count).to.eql 4
				done()

			if msg.type is 'result'
				result_count++
		)

		for i in [1..4]
			handlers['message'] {
				id: id
				data: []
				work: slow_reflex
			}

	it 'should pass data in/out of work function correctly', (done) ->
		id = 'foo'

		data = ['foo', 'bar', {quux: {a: 1, b: null, c: false, d: true}}]

		worker(process_mock (msg) ->
			if msg.type is 'result'
				expect(msg.contents.callback_params).to.eql [null, data.reverse()]
				done()
		)

		handlers['message'] {
			id: id
			data: data
			work: ((data..., cb) ->
				cb null, data.reverse()
			).toString()
		}

	it 'should pass work function errors to master', (done) ->
		id = 'foo'

		data = ['foo', 'bar', {quux: {a: 1, b: null, c: false, d: true}}]

		worker(process_mock (msg) ->
			if msg.type is 'exception'
				expect(msg.contents.is_error).to.be true
				expect(msg.contents.error.type).to.eql 'Error'
				expect(msg.contents.error.parameters.name).to.eql 'Error'
				expect(msg.contents.error.parameters.message).to.eql 'this is a great error'
				done()
		)

		handlers['message'] {
			id: id
			data: data
			work: ((data..., cb) ->
				throw new Error 'this is a great error'
			).toString()
		}

	it 'should pass work function non-error exceptions to master', (done) ->
		id = 'foo'

		data = ['foo', 'bar', {quux: {a: 1, b: null, c: false, d: true}}]

		worker(process_mock (msg) ->
			if msg.type is 'exception'
				expect(msg.contents.is_error).to.be false
				expect(msg.contents.exception).to.eql 'some stupid non-error'
				done()
		)

		handlers['message'] {
			id: id
			data: data
			work: ((data..., cb) ->
				throw (do -> 'some stupid non-error')
			).toString()
		}

	it 'should cause work modules to be required from msg.dirname, when present', (done) ->
		p = process_mock pass

		r = (reqstr) ->
			expect(reqstr).to.match /excellent\/dirname\/whatup\/dude$/
			done()

		worker(p, r)

		handlers['message'] {
			id: 'bar'
			data: [1,2,3]
			dirname: 'excellent/dirname/'
			work: ((data..., cb) ->
				require('whatup/dude')
			).toString()
		}

	it 'should fail when msg.dirname is not present and the work function\'s require argument is a relative path', (done) ->
		p = process_mock (msg) ->
			if msg.type is 'exception'
				expect(msg.contents.error.parameters.message).to.match /dirname/i
				expect(msg.contents.error.parameters.message).to.match /relative/i
				done()

		r = (reqstr) -> undefined

		worker(p)

		handlers['message'] {
			id: 'bar'
			data: [1,2,3]
			work: ((data..., cb) ->
				require('whatup/dude')
			).toString()
		}


	after ->
		mockery.disable()