require('coffee-script').register()
bobbin = require './bobbin.coffee'

pool = bobbin.create()

work = (cb) ->
	foo = 0.5

	console.log 'working...'

	for j in [1..10000]
		foo += Math.random()
		foo /= 2

	cb null, foo

pool.run(work, (err, result) -> console.log(result)) for i in [1..8]