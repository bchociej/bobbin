cluster = require 'cluster'
path = require 'path'
uuid = require 'node-uuid'
num_cpus = require('os').cpus().length

module.exports =
	create: (opts) ->
		workers = []
		handlers = {}

		unless cluster.isMaster is true
			throw new Error 'needs to be cluster master'

		for i in [1..num_cpus]
			cluster.setupMaster exec: path.join(__dirname, 'worker.coffee')

			w = cluster.fork()
			workers.push w

			w.on 'message', (msg) ->
				handlers[msg.id] msg.callback_params...

		get_worker = do ->
			i = 0

			-> workers[i++ % workers.length]

		return {
			run: (data..., work, callback) ->
				unless typeof work is 'function'
					throw new TypeError 'work parameter must be a function'

				unless typeof callback is 'function'
					throw new TypeError 'callback parameter must be a function'

				id = uuid.v1()
				handlers[id] = callback

				get_worker().send
					id: id
					data: data
					work: work.toString()
		}