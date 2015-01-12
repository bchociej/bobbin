mockery = require 'mockery'
expect = require 'expect.js'

describe 'worker', ->

	reflex = ((cb) -> cb()).toString()

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
			expect(msg.id).to.eql id
			done())

		handlers['message'] {
			id: id
			data: []
			work: reflex
		}

	it 'should apply the data to the work function correctly', (done) ->
		id = 'foo'

		data = ['foo', 'bar', {quux: {a: 1, b: null, c: false, d: true}}]

		worker(process_mock (msg) ->
			expect(msg.callback_params).to.eql [null, data.reverse()]
			done()
		)

		handlers['message'] {
			id: id
			data: data
			work: ((data..., cb) ->
				cb null, data.reverse()
			).toString()
		}

	after ->
		mockery.disable()