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
  randomizer: (test) ->
    require('../helpers').randomizerTest nativetype, 1000
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
