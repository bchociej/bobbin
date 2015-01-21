mockery = require 'mockery'
expect = require 'expect.js'

describe 'worker', ->

	reflex = ((cb) -> cb()).toString()

	slow_reflex = ((cb) ->
		setTimeout cb, 10
	).toString()

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

	after ->
		mockery.disable()