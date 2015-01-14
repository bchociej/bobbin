boxed_eval = (s) ->
	### jshint ignore:start ###
	eval "var retval = #{s}"
	retval
	### jshint ignore:end ###

builtin_process = process

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

		unless typeof work_fn is 'function'
			throw new TypeError 'work_fn not a function'

		inc()

		work_fn msg.data..., (err, result) ->
			process.send
				type: 'result'
				contents:
					id: msg.id
					callback_params: [err, result]

			dec()

if require.main is module
	run()
else
	module.exports = run