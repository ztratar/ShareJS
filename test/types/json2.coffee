# Tests for JSON OT type. (src/types/json.coffee)
#
# Spec: https://github.com/josephg/ShareJS/wiki/JSON-Operations

nativetype = require '../../src/types/json2'

randomWord = require './randomWord'

util = require 'util'
p = util.debug
i = util.inspect

# This is an awful function to clone a document snapshot for use by the random
# op generator. .. Since we don't want to corrupt the original object with
# the changes the op generator will make.
clone = (o) -> JSON.parse(JSON.stringify(o))

{randomInt, randomReal} = require('../helpers')

randomKey = (obj) ->
  if Array.isArray(obj)
    if obj.length == 0
      undefined
    else
      randomInt obj.length
  else
    count = 0

    for key of obj
      result = key if randomReal() < 1/++count
    result

# Generate a random new key for a value in obj.
# obj must be an Object.
randomNewKey = (obj) ->
  # There's no do-while loop in coffeescript.
  key = randomWord()
  key = randomWord() while obj[key] != undefined
  key

# Generate a random object
randomThing = ->
  switch randomInt 6
    when 0 then null
    when 1 then ''
    when 2 then randomWord()
    when 3
      obj = {}
      obj[randomNewKey(obj)] = randomThing() for [1..randomInt(5)]
      obj
    when 4 then (randomThing() for [1..randomInt(5)])
    when 5 then randomInt(50)

# Pick a random path to something in the object.
randomPath = (data) ->
  path = []

  while randomReal() > 0.85 and typeof data == 'object'
    key = randomKey data
    break unless key?

    path.push key
    data = data[key]
  
  path

nativetype.generateRandomOp = (data) ->
  pct = 0.95

  container = data: clone(data)

  op = while randomReal() < pct
    pct *= 0.6

    # Pick a random object in the document operate on.
    path = randomPath(container['data'])

    # parent = the container for the operand. parent[key] contains the operand.
    parent = container
    key = 'data'
    for p in path
      parent = parent[key]
      key = p
    operand = parent[key]

    if randomReal() < 0.3 or operand == null
      # Replace

      newValue = randomThing()
      parent[key] = newValue

      {at:path, x:clone(newValue)}

    else if typeof operand == 'string'
      # String. This code is adapted from the text op generator.

      if randomReal() > 0.5 or operand.length == 0
        # Insert
        pos = randomInt(operand.length + 1)
        str = randomWord() + ' '

        parent[key] = operand[...pos] + str + operand[pos..]
        op = {at:path, s:[{p:pos, i:str}]}
        op
      else
        # Delete
        pos = randomInt(operand.length)
        length = Math.min(randomInt(4), operand.length - pos)
        str = operand[pos...(pos + length)]

        parent[key] = operand[...pos] + operand[pos + length..]
        op = {at:path, s:[{p:pos, d:str}]}
        op

    else if typeof operand == 'number'
      # Number
      inc = randomInt(10) - 3
      parent[key] += inc
      {at:path, '+':inc}

    else if Array.isArray(operand)
      # Array

      if randomReal() > 0.5 or operand.length == 0
        # Insert
        pos = randomInt(operand.length + 1)
        obj = randomThing()

        path.push pos
        operand.splice pos, 0, obj
        {at:path, i:clone(obj)}
      else
        # Delete
        pos = randomInt operand.length

        path.push pos
        operand.splice pos, 1
        {d:path}
    else
      # Object
      if randomReal() > 0.5 or Object.keys(operand).length is 0
        # Insert
        k = randomNewKey(operand)
        obj = randomThing()

        path.push k
        operand[k] = obj
        {at:path, i:clone(obj)}
      else
        # Delete
        k = randomKey(operand)

        path.push k
        delete operand[k]
        {d:path}

  [op, container.data]


exports.node =
  move: (test) ->
    xf = (a, b, type='left') -> nativetype.transform a, b, type

    test.deepEqual [], xf [{m:[1,2],to:[2]}], [{d:[1]}]
    test.deepEqual [], xf [{m:[1,2],to:[2]}], [{d:[1,2]}]
    test.deepEqual [m:[1,2],to:[2]], xf [m:[1,2],to:[2]], [d:[3]]
    test.deepEqual [m:[0,2],to:[1]], xf [m:[1,2],to:[2]], [d:[0]]
    test.deepEqual [m:[1,2],to:[2]], xf [m:[1,2],to:[3]], [d:[2]]

    test.deepEqual [m:[2],to:[3]], xf [m:[1],to:[2]], [at:[1],i:3]
    test.deepEqual [m:[0],to:[3]], xf [m:[0],to:[2]], [at:[1],i:3]
    test.deepEqual [m:[0],to:[3,3]], xf [m:[0],to:[2,3]], [at:[1],i:3]

    test.deepEqual [m:[4],to:[2]], xf [m:[4],to:[2]], [x:[],at:[3]]
    test.deepEqual [m:[2],to:[4]], xf [m:[2],to:[4]], [x:[],at:[3]]
    test.deepEqual [], xf [m:[2],to:[4]], [x:[],at:[2]]
    test.deepEqual [], xf [m:[2,3],to:[4,5]], [x:[],at:[2]]
    test.deepEqual [d:[2,3]], xf [m:[2,3],to:[4,5]], [x:[],at:[4]]

    test.deepEqual [i:[],at:[5]], xf [i:[],at:[4]], [m:[2,3],to:[2]]
    test.deepEqual [i:[],at:['b']], xf [i:[],at:['b']], [m:[2,3],to:['a']]
    test.deepEqual [i:[],at:[6]], xf [i:[],at:[5]], [m:[5],to:[4]]
    test.deepEqual [i:[],at:[4]], xf [i:[],at:[5]], [m:[4],to:[5]]

    test.deepEqual [i:[],at:['a','b']], xf [i:[],at:['c']], [m:['c'],to:['a','b']]
    test.deepEqual [i:[],at:[6]], xf [i:[],at:[6]], [m:[6],to:[3,4]]
    test.deepEqual [i:[],at:[3,4,1]], xf [i:[],at:[6,1]], [m:[6],to:[3,4]]
    test.deepEqual [i:[],at:[2,1]], xf [i:[],at:[6,1]], [m:[6],to:[2]]

    test.deepEqual [s:[],at:[4,5]], xf [s:[],at:['a','b']], [m:['a','b'],to:[4,5]]
    test.deepEqual [s:[],at:[4,'b']], xf [s:[],at:['a','b']], [m:['a'],to:[4]]

    test.deepEqual [s:[],at:[5,5]], xf [s:[],at:[4,6]], [m:[4,5],to:[4]]
    test.deepEqual [s:[],at:[5,4]], xf [s:[],at:[4,4]], [m:[4,5],to:[4]]
    test.deepEqual [x:[],at:[5]], xf [x:[],at:[4]], [m:[4,5],to:[4]]

    test.done()

  mvm: (test) ->
    xf = (a, b, type='left') -> nativetype.transform a, b, type
    m = (f, t) -> [m:f,to:t]
    t = (a...) -> test.deepEqual a...

    ###
    t (m ['a'], ['b']), xf (m ['a'], ['b']), (m ['c'], ['d'])
    t (m ['c'], ['b']), xf (m ['a'], ['b']), (m ['a'], ['c']), 'left'
    t [], xf (m ['a'], ['c']), (m ['a'], ['b']), 'right'

    t (m ['b','b'], ['b','c']), xf (m ['a','b'], ['a','c']), (m ['a'], ['b'])
    t (m ['d','b'], ['c']), xf (m ['a','b'], ['c']), (m ['a'], ['d'])
    t (m ['a'], ['d']), xf (m ['a'], ['d']), (m ['a','b'], ['c'])
    ###

    ###
    # Weird little tie-break situation.
    # initial doc is {a:{b:'hi'}}
    #
    # (1) is {m:['a','b'],to:['c']}, (2) is {m:['a'],to:['c']}
    #
    # {a:{b:'hi'}} -(1)-> {a:{},c:'hi'}
    # {a:{b:'hi'}} -(2)-> {c:{b:'hi'}}
    #
    # there are 2 possible convergent final documents:
    # {c:'hi'} or {c:{}}
    #
    # in the first case,  (1') is {m:['c','b'],to:['c']} and (2') is {d:'a'}
    # in the second case, (1') is {d:['c','b']}          and (2') is {m:['a'],to:['c']}
    #
    # in general, we take the left side to 'win', and the other side should
    # delete their source. {c:'hi'} is the final document if (1) is the left
    # op, and {c:{}} is the final document if (2) is the left op.
    #
    t (m ['c','b'], ['c']), xf (m ['a','b'], ['c']), (m ['a'], ['c']), 'left'
    t [d:['a']], xf (m ['a'], ['c']), (m ['a','b'], ['c']), 'right'

    t [d:['c','b']], xf (m ['a','b'], ['c']), (m ['a'], ['c']), 'right'
    t (m ['a'], ['c']), xf (m ['a'], ['c']), (m ['a','b'], ['c']), 'left'
    ####

    ###
    t [], xf [x:1,at:['c','d']], (m ['a'], ['c'])

    t [d:['c']], xf (m ['c'], ['a','b']), (m ['d'], ['a'])
    ###

    ###
    # {a:{b:'ab'}, c:'c'}
    # -(1)-> {a:'ab', c:'c'}
    # -(2)-> {a:'c'}
    # only valid resolutions are {} or {a:'c'}. We take {a:'c'}.
    t [], xf (m ['a','b'], ['a']), (m ['c'], ['a']), 'left'
    t (m ['c'], ['a']), xf (m ['c'], ['a']), (m ['a','b'], ['a']), 'right'
    t [], xf (m ['a','b'], ['a']), (m ['c'], ['a']), 'right'
    t (m ['c'], ['a']), xf (m ['c'], ['a']), (m ['a','b'], ['a']), 'left'
    ####

    ####
    # {a:'a',b:'b'}
    # -(1)-> {b:'a'}
    # -(2)-> {a:'a', c:'b'}
    # only valid resolutions are {} or {b:'a'}.
    t [{d:['c']},{m:['a'],to:['b']}], xf (m ['a'], ['b']), (m ['b'], ['c'])
    t [], xf (m ['b'], ['c']), (m ['a'], ['b'])
    ####

    ###
    # {a:'a',b:'b'}
    # -(1)-> {b:'a'}
    # -(2)-> {a:'b'}
    # only valid resolution is {}
    t [d:['a']], xf (m ['a'], ['b']), (m ['b'], ['a'])
    t [d:['b']], xf (m ['b'], ['a']), (m ['a'], ['b'])
    ####

    ###
    t [d:['a']], xf (m ['a','b'], ['b']), (m ['b', 'a'], ['a'])
    t [d:['b']], xf (m ['b','a'], ['a']), (m ['a', 'b'], ['b'])
    ####

    #t [], xf [i:'3', at:['a']], (m ['b'], ['a'])

    test.done()

  mvm2: (test) ->
    xf = (a, b, type='left') -> nativetype.transform a, b, type
    test.deepEqual [{m:[0],to:[2]}], xf [{m:[0],to:[2]}], [{m:[2],to:[1]}], 'left'
    test.deepEqual [{m:[4],to:[4]}], xf [{m:[3],to:[3]}], [{m:[5],to:[0]}], 'left'
    test.deepEqual [{m:[2],to:[0]}], xf [{m:[2],to:[0]}], [{m:[1],to:[0]}], 'left'
    test.deepEqual [{m:[2],to:[1]}], xf [{m:[2],to:[0]}], [{m:[1],to:[0]}], 'right'
    test.deepEqual [{m:[3],to:[1]}], xf [{m:[2],to:[0]}], [{m:[5],to:[0]}], 'right'
    test.deepEqual [{m:[3],to:[0]}], xf [{m:[2],to:[0]}], [{m:[5],to:[0]}], 'left'
    test.deepEqual [{m:[0],to:[5]}], xf [{m:[2],to:[5]}], [{m:[2],to:[0]}], 'left'
    test.deepEqual [{m:[0],to:[5]}], xf [{m:[2],to:[5]}], [{m:[2],to:[0]}], 'left'
    test.deepEqual [{m:[0],to:[0]}], xf [{m:[1],to:[0]}], [{m:[0],to:[5]}], 'right'
    test.deepEqual [{m:[0],to:[0]}], xf [{m:[1],to:[0]}], [{m:[0],to:[1]}], 'right'
    test.deepEqual [{m:[1],to:[1]}], xf [{m:[0],to:[1]}], [{m:[1],to:[0]}], 'left'
    test.deepEqual [{m:[1],to:[2]}], xf [{m:[0],to:[1]}], [{m:[5],to:[0]}], 'right'
    test.deepEqual [{m:[3],to:[2]}], xf [{m:[2],to:[1]}], [{m:[5],to:[0]}], 'right'
    test.deepEqual [{m:[2],to:[1]}], xf [{m:[3],to:[1]}], [{m:[1],to:[3]}], 'left'
    test.deepEqual [{m:[2],to:[3]}], xf [{m:[1],to:[3]}], [{m:[3],to:[1]}], 'left'
    test.deepEqual [{m:[2],to:[6]}], xf [{m:[2],to:[6]}], [{m:[0],to:[1]}], 'left'
    test.deepEqual [{m:[2],to:[6]}], xf [{m:[2],to:[6]}], [{m:[0],to:[1]}], 'right'
    test.deepEqual [{m:[2],to:[6]}], xf [{m:[2],to:[6]}], [{m:[1],to:[0]}], 'left'
    test.deepEqual [{m:[2],to:[6]}], xf [{m:[2],to:[6]}], [{m:[1],to:[0]}], 'right'
    test.deepEqual [{m:[0],to:[2]}], xf [{m:[0],to:[1]}], [{m:[2],to:[1]}], 'left'
    test.deepEqual [{m:[2],to:[0]}], xf [{m:[2],to:[1]}], [{m:[0],to:[1]}], 'right'
    test.deepEqual [{m:[1],to:[1]}], xf [{m:[0],to:[0]}], [{m:[1],to:[0]}], 'left'
    test.deepEqual [{m:[0],to:[0]}], xf [{m:[0],to:[1]}], [{m:[1],to:[3]}], 'left'
    test.deepEqual [{m:[3],to:[1]}], xf [{m:[2],to:[1]}], [{m:[3],to:[2]}], 'left'
    test.deepEqual [{m:[3],to:[3]}], xf [{m:[3],to:[2]}], [{m:[2],to:[1]}], 'left'
    test.done()

  move2: (test) ->
    li = (p) -> [{at:[p],i:[]}]
    lm = (f,t) -> [{m:[f],to:[t]}]
    xf = nativetype.transform

    test.deepEqual (li 0), xf (li 0), (lm 1, 3), 'left'
    test.deepEqual (li 1), xf (li 1), (lm 1, 3), 'left'
    test.deepEqual (li 1), xf (li 2), (lm 1, 3), 'left'
    test.deepEqual (li 2), xf (li 3), (lm 1, 3), 'left'
    test.deepEqual (li 4), xf (li 4), (lm 1, 3), 'left'

    test.deepEqual (lm 2, 4), xf (lm 1, 3), (li 0), 'right'
    test.deepEqual (lm 2, 4), xf (lm 1, 3), (li 1), 'right'
    test.deepEqual (lm 1, 4), xf (lm 1, 3), (li 2), 'right'
    test.deepEqual (lm 1, 4), xf (lm 1, 3), (li 3), 'right'
    test.deepEqual (lm 1, 3), xf (lm 1, 3), (li 4), 'right'

    test.deepEqual (li 0), xf (li 0), (lm 1, 2), 'left'
    test.deepEqual (li 1), xf (li 1), (lm 1, 2), 'left'
    test.deepEqual (li 1), xf (li 2), (lm 1, 2), 'left'
    test.deepEqual (li 3), xf (li 3), (lm 1, 2), 'left'

    test.deepEqual (li 0), xf (li 0), (lm 3, 1), 'left'
    test.deepEqual (li 1), xf (li 1), (lm 3, 1), 'left'
    test.deepEqual (li 3), xf (li 2), (lm 3, 1), 'left'
    test.deepEqual (li 4), xf (li 3), (lm 3, 1), 'left'
    test.deepEqual (li 4), xf (li 4), (lm 3, 1), 'left'

    test.deepEqual (lm 4, 2), xf (lm 3, 1), (li 0), 'right'
    test.deepEqual (lm 4, 2), xf (lm 3, 1), (li 1), 'right'
    test.deepEqual (lm 4, 1), xf (lm 3, 1), (li 2), 'right'
    test.deepEqual (lm 4, 1), xf (lm 3, 1), (li 3), 'right'
    test.deepEqual (lm 3, 1), xf (lm 3, 1), (li 4), 'right'

    test.deepEqual (li 0), xf (li 0), (lm 2, 1), 'left'
    test.deepEqual (li 1), xf (li 1), (lm 2, 1), 'left'
    test.deepEqual (li 3), xf (li 2), (lm 2, 1), 'left'
    test.deepEqual (li 3), xf (li 3), (lm 2, 1), 'left'

    test.done()

  regression: (test) ->
    xf = (a, b, type='left') -> nativetype.transform a, b, type

    # one paragraph per bug i found with the fuzzer.

    test.deepEqual [], xf [{x:12, at:['sword','boy']}], [{x:'', at:[]}]

    test.deepEqual [], xf [{at:[1], x:''}], [{d:[1]}]
    test.deepEqual [{d:[1]}], xf [{d:[1]}], [{at:[1], x:''}]

    test.deepEqual [{i:'', at:[0]}], xf [{i:'', at:[0]}], [{d:[0]}]

    test.deepEqual [{d:[1]}], xf [{d:[0]}], [{i:'', at:[0]}], 'left'
    test.deepEqual [{d:[1]}], xf [{d:[0]}], [{i:'', at:[0]}], 'right'

    test.deepEqual [{s:[],at:[2]}], xf [{s:[],at:[1]}], [{i:'',at:[1]}]

    test.deepEqual [{i:[],at:[1]}], xf [{i:[],at:[1]}], [{x:'',at:[1]}]

    test.deepEqual [{i:[],at:[1,'a']}], xf [{i:[],at:[0,'a']}], [{i:0,at:[0]}], 'left'
    test.deepEqual [{i:[],at:[1,'a']}], xf [{i:[],at:[0,'a']}], [{i:0,at:[0]}], 'right'

    test.deepEqual [{i:7,at:[3]}], xf [{i:7,at:[3]}], [{x:4,at:[2]}]

    test.deepEqual [{x:'foo',at:['bar']}], xf [{i:'foo',at:['bar']}], [{i:'baz',at:['bar']}], 'left'
    test.deepEqual [], xf [{i:'foo',at:['bar']}], [{i:'baz',at:['bar']}], 'right'

    test.deepEqual [{d:[4]}], xf [{d:[4]}], [{at:[2],x:3}]

    test.deepEqual [], xf [{d:[2]}], [{d:[2]}], 'left'
    test.deepEqual [], xf [{d:[2]}], [{d:[2]}], 'right'

    test.deepEqual [{at:[3,"the"],x:[]}], xf [{at:[3,"the"],x:[]}], [{at:[2],x:null}], 'left'
    test.deepEqual [{at:[3,"the"],x:[]}], xf [{at:[3,"the"],x:[]}], [{at:[2],x:null}], 'right'

    test.deepEqual [{at:[4],s:[{p:2,d:'e'}]}], xf [{at:[4],s:[{p:2,d:'e'}]}], [{at:[2],s:[{p:1,d:'nd'}]}]

    test.deepEqual [{x:4,at:['hi']}], xf [{i:4,at:['hi']}], [{i:'a',at:['hi']}], 'left'
    test.deepEqual [], xf [{i:4,at:['hi']}], [{i:'a',at:['hi']}], 'right'

    test.done()

  ###
  regression1: (test) ->
    #return test.done()
    type = nativetype
    checkSnapshotsEq = (a, b) ->
      if type.serialize
        test.deepEqual type.serialize(a), type.serialize(b)
      else
        test.deepEqual a, b
    {transformLists} = require '../helpers'

    # initial is {"Tumtum":12,"vorpal":"And","the":"the","O":""}
    s_result = {"Tumtum":12,"vorpal":"And","O":""}
    c_result = { vorpal: 'A', the: 'the', O: '' }
    s_ops = [
      [ { at: [ 'the' ], s: [ { p: 2, d: 'e' } ] } ]
      [ { d: [ 'the' ] } ]
    ]
    c_ops = [
      [ { d: [ 'Tumtum' ] } ]
      [ { at: [ 'vorpal' ], s: [ { p: 1, d: 'nd' } ] } ]
    ]


    p "s #{i s_result} c #{i c_result} XF #{i s_ops} x #{i c_ops}"
    [s_, c_] = transformLists type, s_ops, c_ops
    p "XF result #{i s_} x #{i c_}"
    s_c = s_result
    for cop in c_
      p "applying #{i cop} to #{i s_c}"
      s_c = type.apply s_c, cop
    c_s = c_result
    for sop in s_
      p "applying #{i sop} to #{i c_s}"
      c_s = type.apply c_s, sop

    checkSnapshotsEq s_c, c_s
    test.done()
  ###
  randomizer: (test) ->
    require('../helpers').randomizerTest nativetype, 1000
    test.done()
