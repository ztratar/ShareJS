# Tests for JSON OT type. (src/types/json.coffee)
#
# Spec: https://github.com/josephg/ShareJS/wiki/JSON-Operations

nativetype = require '../../src/types/json2'

exports.node =
  simple:
    'Foo': (test) ->
      xf = nativetype.transformEditByComponent
      test.deepEqual { p: ['data',1,1], k: 3 }, xf { p: ['data',1,2], k: 3 }, { p: [1,1], d: true }
      test.deepEqual null, xf { p: ['data',1,2], k: 3 }, { p: [1,2], d: true }
      test.deepEqual { p: ['data'], k: 3 }, xf { p: ['data'], k: 2 }, { p: [1], i:'asdf' }
      test.done()
