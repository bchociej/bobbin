#!/usr/bin/env coffee
require('coffee-script').register()
bobbin = require '../src/bobbin.coffee'

pool = bobbin.create()

work = (i, cb) ->
	foo = 0.5

	#console.log 'working...'

	for j in [1..10000]
		foo += Math.random()
		foo /= 2

	cb null, i

pool.run(i, work, (err, result) -> console.log(result)) for i in [1..20]
