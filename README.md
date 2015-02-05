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

---

Author: Ben Chociej <ben@chociej.io>

bobbin is copyright © 2015 Ben Chociej. See the LICENSE file for a non-exclusive, limited license (the MIT license) that is freely extended to anyone wishing to use bobbin. If you do not agree to the terms of the LICENSE, you may not copy or use bobbin at all.

THIS SOFTWARE AND ASSOCIATED DOCUMENTATION ("THE SOFTWARE") IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

TERMS OF CONTRIBUTION

If you want to contribute to bobbin, you must allow the author to freely distribute your contributions under bobbin's LICENSE. Your contributions must be legally allowed to be distributed by the author under the terms of the LICENSE.

If you contribute something that you don't own or can't legally allow the author to distribute under the LICENSE, you have to legally defend and financially compensate the author and other contributors from any dispute that arises because of your contributions.

In other words, if you contribute something to bobbin that, whether you know it or not, you and/or the author cannot legally distribute under the terms of the LICENSE, you agree to indemnify, defend, and hold harmless the author (Ben Chociej) and any other contributors or users from and against any loss, expense, liability, damage, and/or claim (including reasonable attorneys’ fees) arising from the use and/or redistribution of your contributions.

By pushing to the bobbin github repository, or initiating a pull request to it, or contributing to bobbin in any other way, you signify that you agree to these terms.

These terms are repeated in the CONTRIBUTING file for clarity.