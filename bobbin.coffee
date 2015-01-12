cluster = require 'cluster'
uuid = require 'node-uuid'

num_cpus = require('os').cpus().length

workers = []
handlers = {}

unless cluster.isMaster
	throw new Error 'needs to be cluster master'

module.exports =
	create: (opts) ->
		for i in [1..num_cpus]
			cluster.setupMaster exec: './worker.js'

			w = cluster.fork()
			workers.push w

			w.on 'message', (msg) ->
				handlers[msg.id] msg.callback_params...

		get_worker = do ->
			i = 0

			-> workers[i % workers.length]

		return {
			run: (data..., work, callback) ->
				id = uuid.v1()
				handlers[id] = callback

				get_worker().send
					id: id
					data: data
					work: work.toString()
		}