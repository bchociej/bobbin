cluster = require 'cluster'
path = require 'path'
uuid = require 'node-uuid'
num_cpus = require('os').cpus().length

module.exports =
	create: (num_workers) ->
		workers = []
		worker_queue = []
		empty = []
		handlers = {}
		killing = false

		unless cluster.isMaster is true
			throw new Error 'needs to be cluster master'

		unless typeof num_workers is 'number' and num_workers >= 1
			num_workers = num_cpus

		cluster.setupMaster exec: path.join(__dirname, 'worker.coffee')

		worker_msg_handler = (num) ->
			(msg) ->
				switch msg.type
					when 'result'
						handlers[msg.contents.id] msg.contents.callback_params...

					when 'empty'
						worker_queue = worker_queue.filter (x) -> x isnt num
						worker_queue.unshift num
						empty[num] = true

						if killing
							workers[num].kill()


		for i in [0...num_workers]
			w = cluster.fork()
			w.__num__ = i
			workers.push w
			worker_queue.unshift i
			empty.push false

			w.on 'message', worker_msg_handler(i)

		get_worker = ->
			worker_queue.push worker_queue.shift()
			workers[worker_queue[worker_queue.length - 1]]

		return {
			run: (data..., work, callback) ->
				if killing
					throw new Error 'kill has been called, no new work accepted'

				unless typeof work is 'function'
					throw new TypeError 'work parameter must be a function'

				unless typeof callback is 'function'
					throw new TypeError 'callback parameter must be a function'

				id = uuid.v1()
				handlers[id] = callback

				w = get_worker()

				w.send
					id: id
					data: data
					work: work.toString()

				empty[w.__num__] = false

			kill: (timeout=0) ->
				unless typeof timeout is 'number' and timeout >= 0
					throw new TypeError 'kill timeout must be a non-negative number of milliseconds'

				unless killing
					killing = true
					
					for w in workers
						if timeout is 0 or empty[w.__num__]
							w.kill()
						else
							setTimeout w.kill, timeout
		}