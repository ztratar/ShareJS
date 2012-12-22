# This is the implementation of the JSON OT type.
#
# Spec is here: https://github.com/josephg/ShareJS/wiki/JSON-Operations

if WEB?
  text = exports.types.text2
else
  text = require './text2'

json = {}

json.name = 'json'

json.create = -> null

json.checkValidOp = (op) ->

isArray = (o) -> Object.prototype.toString.call(o) == '[object Array]'
isObject = (o) -> o.constructor is Object
json.checkList = (elem) ->
  throw new Error 'Referenced element not a list' unless isArray(elem)

json.checkObj = (elem) ->
  throw new Error "Referenced element not an object (it was #{JSON.stringify elem})" unless isObject elem

json.apply = (snapshot, op) ->
  json.checkValidOp op
  op = clone op

  container = {data: clone snapshot}

  try
    for c, i in op
      elem = container
      key = 'data'

      for p in c.p
        elem = elem[key]
        key = p

        throw new Error 'Path invalid' unless parent?

      if c['+'] != undefined
        # Number add
        throw new Error 'Referenced element not a number' unless typeof elem[key] is 'number'
        elem[key] += c['+']

      else if c.s
        # String insert
        throw new Error "Referenced element not a string (it was #{JSON.stringify elem})" unless typeof elem is 'string'
        elem[key] = text.apply elem[key], c.s

      else if c.i != undefined and c.d
        elem[key] = c.i

      else if c.i != undefined
        if typeof key is 'number'
          # list
          elem.splice key, 0, c.i
        else
          elem[key] = c.i

      else if c.d
        if typeof key is 'number'
          elem.splice key, 1
        else
          delete elem[key]

      else if c.m != undefined
        data = elem[key]
        if typeof key is 'number'
          elem.splice key, 1
        else
          delete elem[key]

        # TODO: this is the same path traversal as above; we should extract
        # this functionality.
        targetParent = null
        targetParentkey = null
        targetElem = container
        targetKey = 'data'
        for p in c.m
          targetParent = targetElem
          targetParentkey = targetKey
          targetElem = targetElem[targetKey]
          targetKey = p

          throw new Error 'Path invalid' unless targetParent?
        if typeof targetKey is 'number'
          targetElem.splice targetKey, 0, data
        else
          targetElem[targetKey] = data

      else
        throw new Error 'invalid / missing instruction in op'

  catch error
    # TODO: Roll back all already applied changes. Write tests before implementing this code.
    throw error

  container.data

# Checks if two paths, p1 and p2 match.
json.pathMatches = (p1, p2, ignoreLast) ->
  return false unless p1.length == p2.length

  for p, i in p1
    return false if p != p2[i] and (!ignoreLast or i != p1.length - 1)

  true

json.append = (dest, c) ->
  c = clone c
  dest.push c
  ###
  if dest.length != 0 and json.pathMatches c.p, (last = dest[dest.length - 1]).p
    if last.na != undefined and c.na != undefined
      dest[dest.length - 1] = { p: last.p, na: last.na + c.na }
    else if last.li != undefined and c.li == undefined and c.ld == last.li
      # insert immediately followed by delete becomes a noop.
      if last.ld != undefined
        # leave the delete part of the replace
        delete last.li
      else
        dest.pop()
    else if last.od != undefined and last.oi == undefined and
        c.oi != undefined and c.od == undefined
      last.oi = c.oi
    else if c.lm != undefined and c.p[c.p.length-1] == c.lm
      null # don't do anything
    else
      dest.push c
  else
    dest.push c
  ###

json.compose = (op1, op2) ->
  json.checkValidOp op1
  json.checkValidOp op2

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

# hax, copied from test/types/json. Apparently this is still the fastest way to deep clone an object, assuming
# we have browser support for JSON.
# http://jsperf.com/cloning-an-object/12
clone = (o) -> JSON.parse(JSON.stringify o)

# Returns true if an op at otherPath may affect an op at path
json.canOpAffectOp = (otherPath, path) ->
  return true if otherPath.length == 0
  return false if path.length == 0

  path = path[...path.length-1]
  otherPath = otherPath[...otherPath.length-1]

  for p,i in otherPath
    if i >= path.length
      return false
    if p != path[i]
      return false

  # Same
  return true

transformPathByOp = (p, c) ->
  return p unless c.i? or c.d or c.m?
  return p if c.d and c.i?

  if c.m?
    if (json.canOpAffectOp c.p, p) and p[c.p.length-1] == c.p[c.p.length-1]
      return c.m.concat p[c.p.length-1..]
    return

  # if c is inserting into an object, nothing to do.
  return p if typeof c.p[c.p.length-1] isnt 'number'
  return p unless json.canOpAffectOp c.p, p
  if c.p[c.p.length-1] <= p[p.length-1]
    newP = p[..]
    newP[c.p.length-1] += if c.d then -1 else 1
    newP
  else
    p

arrayEq = (a, b) ->
  return false unless a.length is b.length
  for x, i in a
    return false unless b[i] == x
  return true

Array::isPrefixOf = (b) ->
  return false if @length > b.length
  for x,i in this
    return false unless b[i] is x
  true
    
editForPath = (p) ->
  p = ['data'].concat(p)
  k = p.pop()
  {p, k}

# true if e is contained inside otherE
editContainsEdit = (otherE, e) ->
  console.log 'in eCe', otherE, e
  if e.p.length < otherE.p.length
    return false
  else if e.p.length == otherE.p.length
    return arrayEq(e.p, otherE.p) and e.k == otherE.k
  else
    return false unless otherE.p.isPrefixOf e.p
    return e.p[otherE.p.length] == otherE.k

json.transformEditByComponent = transformEditByComponent = (edit, c) ->
  cEdit = editForPath c.p
  switch
    when c.d
      # edit might be inside a deleted region
      if editContainsEdit cEdit, edit
        console.log 'edit does contain edit'
        null
      # edit is [1,2]/3 and c deletes [1]/1.
      else if typeof cEdit.k is 'number' and cEdit.p.isPrefixOf(edit.p) and cEdit.k < edit.p[cEdit.p.length]
        edit.p = edit.p[..]
        edit.p[cEdit.p.length]--
        edit
      else
        edit
    when c.i?
      if cEdit.p.isPrefixOf(edit.p)
        edit.p = edit.p[..]
        if cEdit.p.length is edit.p.length
          if cEdit.k <= edit.k
            edit.k++
        else if cEdit.k <= edit.p[cEdit.p.length]
          edit.p[cEdit.p.length]++
      edit
    when c.m
      # cases:
      # - We were moved
      # - ...
      if editContainsEdit cEdit, edit
        dest = editForPath c.m
        # Our path moves
        if edit.p.length == cEdit.p.length
          dest
        else
          # We're contained in an object that moves
          edit.p = dest.p.concat(dest.k).concat(edit.p[cEdit.p.length..])
          edit
      else
        edit
    else
      throw 'asdf'


editsForComponent = (c) ->
  switch
    when c.s or c['+']? or (c.i isnt undefined and c.d)
      # Technically, we could have src and dest, but we only need one
      { src: editForPath c.p }
    when c.i isnt undefined
      dest: editForPath c.p
    when c.d
      { src: editForPath c.p }
    when c.m?
      src = editForPath c.p
      if typeof c.m in ['string', 'number']
        dest = {p:src.p, k:c.m}
      else
        dest = editForPath c.m
      {src, dest}

# transform c so it applies to a document with otherC applied.
json.transformComponent = (dest, c, otherC, type) ->
  cEdits = editsForComponent c
  otherCEdits = editsForComponent otherC


  if c.s
    # transform its path by any modifications made by otherC
    # so if otherC inserts into a list above us
    # or deletes
    # or moves
    asdf()




  c = clone c
  c.p.push(0) if c.na != undefined
  otherC.p.push(0) if otherC.na != undefined

  common = otherC.p.length - 1 if json.canOpAffectOp otherC.p, c.p

  cplength = c.p.length
  otherCplength = otherC.p.length

  c.p.pop() if c.na != undefined # hax
  otherC.p.pop() if otherC.na != undefined


  # |common| will be > 0 iff the two components share a prefix of any length in
  # their path. Two components are completely independent if they share no
  # prefix, so we ignore that case here.
  if common?
    commonOperand = cplength == otherCplength
    # transform based on otherC
    if otherC.na != undefined
      # this case is handled above due to icky path hax
    else if otherC.si != undefined || otherC.sd != undefined
      # String op vs string op - pass through to text type
      if c.si != undefined || c.sd != undefined
        throw new Error("must be a string?") unless commonOperand

        # Convert an op component to a text op component
        convert = (component) ->
          newC = p:component.p[component.p.length - 1]
          if component.si
            newC.i = component.si
          else
            newC.d = component.sd
          newC

        tc1 = convert c
        tc2 = convert otherC
          
        res = []
        text._tc res, tc1, tc2, type
        for tc in res
          jc = { p: c.p[...common] }
          jc.p.push(tc.p)
          jc.si = tc.i if tc.i?
          jc.sd = tc.d if tc.d?
          json.append dest, jc
        return dest
    else if otherC.li != undefined && otherC.ld != undefined
      if otherC.p[common] == c.p[common]
        # noop
        if !commonOperand
          # we're below the deleted element, so -> noop
          return dest
        else if c.ld != undefined
          # we're trying to delete the same element, -> noop
          if c.li != undefined and type == 'left'
            # we're both replacing one element with another. only one can
            # survive!
            c.ld = clone otherC.li
          else
            return dest
    else if otherC.li != undefined
      if c.li != undefined and c.ld == undefined and commonOperand and c.p[common] == otherC.p[common]
        # in li vs. li, left wins.
        if type == 'right'
          c.p[common]++
      else if otherC.p[common] <= c.p[common]
        c.p[common]++

      if c.lm != undefined
        if commonOperand
          # otherC edits the same list we edit
          if otherC.p[common] <= c.lm
            c.lm++
          # changing c.from is handled above.
    else if otherC.ld != undefined
      if c.lm != undefined
        if commonOperand
          if otherC.p[common] == c.p[common]
            # they deleted the thing we're trying to move
            return dest
          # otherC edits the same list we edit
          p = otherC.p[common]
          from = c.p[common]
          to = c.lm
          if p < to || (p == to && from < to)
            c.lm--

      if otherC.p[common] < c.p[common]
        c.p[common]--
      else if otherC.p[common] == c.p[common]
        if otherCplength < cplength
          # we're below the deleted element, so -> noop
          return dest
        else if c.ld != undefined
          if c.li != undefined
            # we're replacing, they're deleting. we become an insert.
            delete c.ld
          else
            # we're trying to delete the same element, -> noop
            return dest
    else if otherC.lm != undefined
      if c.lm != undefined and cplength == otherCplength
        # lm vs lm, here we go!
        from = c.p[common]
        to = c.lm
        otherFrom = otherC.p[common]
        otherTo = otherC.lm
        if otherFrom != otherTo
          # if otherFrom == otherTo, we don't need to change our op.

          # where did my thing go?
          if from == otherFrom
            # they moved it! tie break.
            if type == 'left'
              c.p[common] = otherTo
              if from == to # ugh
                c.lm = otherTo
            else
              return dest
          else
            # they moved around it
            if from > otherFrom
              c.p[common]--
            if from > otherTo
              c.p[common]++
            else if from == otherTo
              if otherFrom > otherTo
                c.p[common]++
                if from == to # ugh, again
                  c.lm++

            # step 2: where am i going to put it?
            if to > otherFrom
              c.lm--
            else if to == otherFrom
              if to > from
                c.lm--
            if to > otherTo
              c.lm++
            else if to == otherTo
              # if we're both moving in the same direction, tie break
              if (otherTo > otherFrom and to > from) or
                 (otherTo < otherFrom and to < from)
                if type == 'right'
                  c.lm++
              else
                if to > from
                  c.lm++
                else if to == otherFrom
                  c.lm--
      else if c.li != undefined and c.ld == undefined and commonOperand
        # li
        from = otherC.p[common]
        to = otherC.lm
        p = c.p[common]
        if p > from
          c.p[common]--
        if p > to
          c.p[common]++
      else
        # ld, ld+li, si, sd, na, oi, od, oi+od, any li on an element beneath
        # the lm
        #
        # i.e. things care about where their item is after the move.
        from = otherC.p[common]
        to = otherC.lm
        p = c.p[common]
        if p == from
          c.p[common] = to
        else
          if p > from
            c.p[common]--
          if p > to
            c.p[common]++
          else if p == to
            if from > to
              c.p[common]++
    else if otherC.oi != undefined && otherC.od != undefined
      if c.p[common] == otherC.p[common]
        if c.oi != undefined and commonOperand
          # we inserted where someone else replaced
          if type == 'right'
            # left wins
            return dest
          else
            # we win, make our op replace what they inserted
            c.od = otherC.oi
        else
          # -> noop if the other component is deleting the same object (or any
          # parent)
          return dest
    else if otherC.oi != undefined
      if c.oi != undefined and c.p[common] == otherC.p[common]
        # left wins if we try to insert at the same place
        if type == 'left'
          json.append dest, {p:c.p, od:otherC.oi}
        else
          return dest
    else if otherC.od != undefined
      if c.p[common] == otherC.p[common]
        return dest if !commonOperand
        if c.oi != undefined
          delete c.od
        else
          return dest
  
  json.append dest, c
  return dest

if WEB?
  exports.types ||= {}

  # This is kind of awful - come up with a better way to hook this helper code up.
  exports._bt(json, json.transformComponent, json.checkValidOp, json.append)

  # [] is used to prevent closure from renaming types.text
  exports.types.json = json
else
  module.exports = json

  require('./helpers').bootstrapTransform(json, json.transformComponent, json.checkValidOp, json.append)
