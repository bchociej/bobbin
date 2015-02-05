#!/usr/bin/env coffee
require('coffee-script').register()

async = require 'async'
path = require 'path'

bobbin = require '../src/bobbin.coffee'

async.series [



	# Example 1: Hello World
	(example_cb) ->
		bobbin.create (err, pool) ->
			return example_cb(err) if err?

			# Work function says hello world and how many times run
			work_function = (n, callback) ->
				console.log "Hello World #{n}!"
				callback()

			# use caolan/async to manage async calls
			async.times 5, (n, callback) ->

				# call the Hello World work function with n injected
				pool.run n, work_function, callback

			, (err) ->
				return example_cb(err) if err?
				console.log 'Example 1 Done!\n'
				example_cb()



	# Example 2: Module Pathname Injection
	, (example_cb) ->
		# Define some options, including the working directory for this pool
		opts = {
			work_dir: path.resolve(__dirname, './path/name/injection/example/')
			num_workers: 5
		}

		# Pass opts into bobbin.create this time
		bobbin.create opts, (err, pool) ->
			return example_cb(err) if err?

			# Print the string exported from the example module.
			# require() will look for the module in opts.work_dir
			work_function = (callback) ->
				console.log require('./module.coffee')
				callback()


			pool.run work_function, (err) ->
				return example_cb(err) if err?
				console.log 'Example 2 Done!\n'
				example_cb()



], (err) ->
	if err?
		console.error 'There was an error!'
		console.error err
		console.trace err
		process.exit -1

	console.log 'Examples finished!'
	process.exit 0