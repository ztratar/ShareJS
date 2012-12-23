# This is the implementation of the JSON OT type.
#
# Spec is here: https://github.com/josephg/ShareJS/wiki/JSON-Operations

if WEB?
  text = exports.types.text2
else
  text = require './text'

json = {}

json.name = 'json'

json.create = -> null

json.checkValidOp = (op) ->

Array::isPrefixOf = (b) ->
  return false if @length > b.length
  for x,i in this
    return false unless b[i] is x
  true
# hax, copied from test/types/json. Apparently this is still the fastest way to deep clone an object, assuming
# we have browser support for JSON.
# http://jsperf.com/cloning-an-object/12
clone = (o) -> JSON.parse(JSON.stringify o)
isArray = (o) -> Object.prototype.toString.call(o) == '[object Array]'
isObject = (o) -> o.constructor is Object
init = (a) -> a[...a.length-1]
last = (a) -> a[a.length-1]
def = (x) -> typeof x != 'undefined'
merge = (a,b) ->
  f = {}
  for k,v of a
    f[k] = v unless k of b
  for k,v of b
    f[k] = v
  f
arrayEq = (a,b) ->
  return false unless a.length == b.length
  for x,i in a
    return false unless x == b[i]
  return true

ek = (container, p) ->
  elem = container
  key = 'data'

  for k in p
    elem = elem[key]
    key = k

  [elem, key]

json.apply = (snapshot, op) ->
  container = {data: clone snapshot}

  for c in op
    if typeof c['+'] != 'undefined'
      [elem, key] = ek(container, c.at)
      elem[key] += c['+']

    else if typeof c.s != 'undefined'
      [elem, key] = ek(container, c.at)
      elem[key] = text.apply elem[key], c.s

    else if typeof c.x != 'undefined'
      [elem, key] = ek(container, c.at)
      elem[key] = clone c.x

    else if typeof c.i != 'undefined'
      [elem, key] = ek(container, c.at)
      if typeof key is 'number'
        elem.splice key, 0, clone c.i
      else
        elem[key] = clone c.i

    else if c.d
      [elem, key] = ek(container, c.d)
      if typeof key is 'number'
        elem.splice key, 1
      else
        delete elem[key]

    else
      throw new Error 'invalid / missing instruction in op'

  container.data

json.append = (dest, c) ->
  dest.push c

json.compose = (op1, op2) ->
  # TODO: can probably get away with just slice() here.
  newOp = clone op1
  json.append newOp, c for c in op2

  newOp

json.normalize = (op) ->
  newOp = []
  
  op = [op] unless isArray op

  for c in op
    c.p ?= []
    json.append newOp, c
  
  newOp



################################################################
# TRANSFORM

updatePathForD = (p, op) ->
  return null if op.length is 0
  p = p[..]
  if init(op).isPrefixOf(p)
    if last(op) == p[op.length-1]
      return null
    else if typeof last(op) is 'number' and last(op) < p[op.length-1]
      p[op.length-1]--
  return p

updatePathForI = (p, op, meFirst) ->
  p = p[..]
  if typeof last(op) isnt 'number' and arrayEq(p, op)
    if meFirst
      return p
    else
      return null
  return p if typeof last(op) isnt 'number'
  if init(op).isPrefixOf(p)
    if last(op) == p[op.length-1]
      unless p.length == op.length and meFirst
        p[op.length-1]++
    else if last(op) < p[op.length-1]
      p[op.length-1]++
  return p

updatePathForM = (p, mfrom, mto, meFirst) ->
  # this assumes the updated op is not also an m, there be dragons
  p = updatePathForD p, mfrom
  mto = updatePathForD mto, mfrom
  p = updatePathForI p, mto, meFirst
  p


# ops are: s,+,d,i,x,m. 36 cases, 12 trivial = 24.
transform = (c, oc, type) ->
  if def(oc['+'])
    # this is the easy one
    return clone c
  else if def(oc.s)
    # subop
    if def(c.s) and arrayEq c.at, oc.at
      return {at:c.at, s:text.transform c.s, oc.s, type}
    return clone c

  if oc.d
    switch
      when c.at # i, s, +, x
        # i and d at the same place --> i carries on
        if def(c.i) and arrayEq c.at, oc.d
          return c
        p = updatePathForD c.at, oc.d
        if p?
          return merge(c,{at:p})
      when c.d
        if arrayEq c.d, oc.d
          return undefined
        else
          p = updatePathForD c.d, oc.d
          if p?
            return {d:p}
      when def(c.m)
        # what do if i move a from inside b to outside b, and b is deleted?
        throw 'ahhh'
  else if def(oc.i)
    switch
      when c.at # i, s, +, x
        p = updatePathForI c.at, oc.at, def(c.i) and type is 'left'
        if p?
          return merge(c,{at:p})
      when c.d
        p = updatePathForI c.d, oc.at
        if p?
          return {d:p}
      when def(c.m)
        throw 'ahhh'
  else if def(oc.x)
    switch
      when typeof c.x != 'undefined'
        if arrayEq c.at, oc.at
          # two clients replacing the same thing
          if type is 'left'
            return clone c
          else
            return clone oc
        else
          p = updatePathForD c.at, oc.at
          if p?
            return c
      when c.at # i, s, +, x
        if def(c.i) and arrayEq c.at, oc.at
          return c
        p = updatePathForD c.at, oc.at
        if p?
          return c
      when c.d
        if arrayEq c.d, oc.at
          # delete wins
          return c
        p = updatePathForD c.d, oc.at
        if p?
          return c
      when def(c.m)
        throw 'ahhh'
  else if def(oc.m)
    throw 'ahhh'

json.transformComponent = (dest, c, otherC, type) ->
  c_ = transform c, otherC, type
  if c_?
    json.append dest, clone c_

  #util = require 'util'
  #util.debug util.format '%j against %j (%s) gives %j', c, otherC, type, c_
  return dest


#################################################################


if WEB?
  exports.types ||= {}

  # This is kind of awful - come up with a better way to hook this helper code up.
  exports._bt(json, json.transformComponent, json.checkValidOp, json.append)

  # [] is used to prevent closure from renaming types.text
  exports.types.json = json
else
  module.exports = json

  require('./helpers').bootstrapTransform(json, json.transformComponent, json.checkValidOp, json.append)
