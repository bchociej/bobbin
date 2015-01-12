boxed_eval = (s) ->
	eval "var retval = #{s}"
	retval

cluster = require 'cluster'

unless cluster.isWorker
	throw new Error 'needs to be cluster worker'

process.on 'message', (msg) ->
	work_fn = boxed_eval msg.work

	unless typeof work_fn is 'function'
		throw new TypeError 'work_fn not a function'

	work_fn msg.data..., (err, result) ->
		process.send
			id: msg.id
			callback_params: [null, result]