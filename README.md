# bobbin
easily spool up thread-like worker processes in node with bobbin

[![NPM](https://nodei.co/npm/bobbin.png?compact=true)](https://nodei.co/npm/bobbin/)

```javascript
// to create a pool of workers:

var bobbin = require('bobbin');

// create 4 processes; defaults to os.cpus().length
bobbin.create(4, function(err, pool) {

	// to send some work (in this case concatenate two strings `left' and `right'):

	var left = 'foo', right = 'bar';
	pool.run(
		left, right, // you have to explicitly pass variables
		function remoteWorkFunction(left, right, callback) {
	    	callback(left + right);
	    },
	    function localCallback(result) {
	    	assert(result === 'foobar');
	    }
	);

});
```

for clarity, the signature of `pool.run` is:

```javascript
pool.run(varsToSend..., workFunction, localCallback)
```

stuff to keep in mind:

1. calls to `pool.run()` are dispatched to workers in a round-robin fashion, though idle workers are prioritized.
2. you can't send closures to workers, so explicitly send data in the first arguments to `pool.run()`. those arguments will be passed verbatim into your work function.
3. your local callback gets called with whatever your work function calls back with.
4. to `create()` a pool, you have to be the `cluster` master, i.e. `cluster.isMaster`

Apache License 2.0, see LICENSE for info.

