cluster = require 'cluster'
path = require 'path'
fs = require 'fs'
uuid = require 'node-uuid'
num_cpus = require('os').cpus().length



# Some custom Error types for clear debugging

# Wraps an error from a worker
WorkerError = (e) ->
	this.message = e.message
	this.filename = e.filename
	this.lineNumber = e.lineNumber
	this.name = e.name
	this.workerStack = e.stack

# Signifies that the error was in Bobbin code, not the work function
BobbinError = (message) ->
	this.message = message

WorkerError.prototype = BobbinError.prototype = new Error

module.exports =
	WorkerError: WorkerError

	BobbinError: BobbinError

	create: (opts, create_cb) ->
		workers = []
		worker_queue = []
		empty = []
		handlers = {}
		killing = false



		# If only one arg, callback is first position.
		unless create_cb?
			create_cb = opts



		# Would like to remove this restriction. I think it's safe to do so.
		unless cluster.isMaster is true
			return create_cb new Error 'needs to be cluster master'



		# Process options. If string, it's a path. If number, num_workers.
		num_workers = work_dir = undefined

		if typeof opts is 'number'
			num_workers = opts
		else if typeof opts is 'string'
			work_dir = opts
		else if typeof opts is 'object' and not Array.isArray(opts)
			{num_workers, work_dir, cache_functions} = opts

		unless typeof num_workers is 'number'
			num_workers = num_cpus

		if num_workers > 1024 or num_workers < 1 or isNaN(num_workers)
			return create_cb new Error "num_workers is nonsensical (#{num_workers})"

		unless typeof work_dir is 'string'
			work_dir = path.resolve('.')

		cache_functions ?= true



		# We aren't forking this script, use the worker script!
		cluster.setupMaster {
			exec: path.join(__dirname, 'worker.coffee')
		}



		# Unified handling of messages that come back from worker processes
		worker_msg_handler = (num) ->
			(msg) ->
				switch msg.type
					when 'result'
						handlers[msg.contents.id] msg.contents.callback_params...

					when 'exception'
						if msg.contents.is_error
							handlers[msg.contents.id] (new WorkerError msg.contents.error.parameters)
						else
							handlers[msg.contents.id] msg.contents.exception

					when 'empty'
						worker_queue = worker_queue.filter (x) -> x isnt num
						worker_queue.unshift num
						empty[num] = true

						if killing
							workers[num].kill()



		# Start workers and organize the queue
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



		# Builds a pool object, with a specified working directory
		contextualized_pool = (dir, con_pool_cb) ->
			unless typeof dir is 'string'
				return con_pool_cb new TypeError 'dir must be a string'

			fs.stat dir, (err, stats) ->
				if err?
					return con_pool_cb err

				unless stats.isDirectory()
					return con_pool_cb new Error "not a directory: #{dir}"

				con_pool_cb null, {
					run: (data..., work, run_cb) ->
						unless typeof run_cb is 'function'
							run_cb = -> undefined

						if killing
							return run_cb new BobbinError 'kill has been called, no new work accepted'

						unless typeof work is 'function'
							run_cb new BobbinError 'work must be a function'

						id = uuid.v1()
						handlers[id] = run_cb

						w = get_worker()

						w.send
							id: id
							data: data
							work: work.toString()
							cache_function: if cache_functions then true else false
							dirname: dir

						empty[w.__num__] = false

					kill: (timeout=0, kill_cb) ->
						unless kill_cb?
							kill_cb = timeout
							timeout = 0

						unless typeof kill_cb is 'function'
							kill_cb = -> undefined

						unless typeof timeout is 'number' and timeout >= 0
							return kill_cb new BobbinError 'kill timeout must be a non-negative number of milliseconds'

						unless killing
							killing = true

							if timeout is 0
								w.kill() for w in workers
								return kill_cb()
							else
								_killed = 0
								_kill = ->
									if ++_killed is workers.length
										kill_cb()

								workers.forEach (w) ->
									if empty[w.__num__]
										w.kill()
										_kill()
									else
										setTimeout ->
											w.kill()
											_kill()
										, timeout

					path: (dir, path_cb) -> contextualized_pool(dir, path_cb)
				}



		# Finally, create a pool and call back
		return contextualized_pool work_dir, create_cb
