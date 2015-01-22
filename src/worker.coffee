path = require 'path'

boxed_eval = (s) ->
	### jshint ignore:start ###
	eval "var retval = #{s}"
	retval
	### jshint ignore:end ###

box_error = (e) ->
	unless e instanceof Error
		throw new TypeError 'e is not an Error'

	{
		type: e.constructor.name
		parameters: {
			name: e.name
			message: e.message
			filename: e.filename
			lineNumber: e.lineNumber
			stack: e.stack
		}
	}

builtin_process = process
real_require = require

run = (process = builtin_process) ->
	cluster = require 'cluster'

	unless cluster.isWorker
		throw new Error 'needs to be cluster worker'

	count = 0
	inc = -> count++
	dec = ->
		count = Math.max(0, count - 1)

		if count is 0
			process.send {type: 'empty'}

	process.on 'message', (msg) ->
		work_fn = boxed_eval msg.work

		require = (what) ->
			if msg.dirname? and what.indexOf path.sep > -1
				real_require path.resolve(msg.dirname, what)
			else real_require what

		unless typeof work_fn is 'function'
			throw new TypeError 'work_fn not a function'

		inc()

		try
			work_fn msg.data..., (err, result) ->
				process.send
					type: 'result'
					contents:
						id: msg.id
						callback_params: [err, result]

				dec()
		catch e
			if e instanceof Error
				e = box_error e

				process.send
					type: 'exception'
					contents:
						id: msg.id
						is_error: true
						error: e

			else
				process.send
					type: 'exception'
					contents:
						id: msg.id
						is_error: false
						exception: e

			dec()

if require.main is module
	run()
else
	module.exports = run