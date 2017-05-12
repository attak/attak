extend = require 'extend'
express = require 'express'

rawFields = ['string']

class ComponentManager

  constructor: () ->
    @router = new express.Router
    @listeners = {}
    @components = {}

  add: (component) ->
    @components[component.guid] = component
    @listeners[component.guid] = (req, res, next) =>
      plan = req.body
      params = req.params

      res.handle component, params, plan, (err, results) =>
        console.log "TRIGGER RESULTS", err, results

    structure = component.structure

    flattened = @flattenObject structure
    for urlPath, subscribeTo of flattened
      changeUrl = "/#{component.namespace}/#{urlPath}"
      @router.all subscribeTo, @listeners[component.guid]

  getNamespaces: (structure, namespace='', namespaces=[]) ->
    for key, val of structure
      namespace += "#{}/"

  remove: (guid) ->
    delete @components[guid]

  notifyChange: (fromNamespace, path, plan, oldState, newState, diffs, opts, callback) ->
    if opts.preventNotify
      return callback null, plan

    console.log "TOP LEVEL NOTIFY", fromNamespace, path, newState
    response =
      handle: (component, params, plan, nextHandler) =>
        notifyOpts = extend true, {}, opts
        notifyOpts.preventNotify = true
        notifyOpts.fromNamespace = fromNamespace
        console.log "NOTIFY HANDLE", component.namespace, fromNamespace, notifyOpts.target
        component.planResolution oldState, newState, diffs, notifyOpts, (err, newPlan) ->
          plan = [plan..., newPlan...]
          callback null, plan

    request =
      method: 'POST'
      body:
        plan: plan
        path: path
        oldState: oldState
        newState: newState
      url: "/#{path.join '/'}"

    # Express router sometimes calls back multiple times for 
    # unhandled changes, so we ignore subsequent ones
    hasCalledBack = false
    @router.handle request, response, (err) ->
      if hasCalledBack is false
        hasCalledBack = true
        console.log "UNHANDLED STATE CHANGE EVENT", request.url
        callback err, plan

  flattenObject: (ob) ->
    what = Object.prototype.toString
    toReturn = {}
    for i of ob
      if !ob.hasOwnProperty(i)
        continue
      result = what.call(ob[i])
      if result == '[object Object]' or result == '[object Array]'
        flatObject = @flattenObject(ob[i])
        for x of flatObject
          if !flatObject.hasOwnProperty(x)
            continue
          toReturn[i + '/' + x] = flatObject[x]
      else
        toReturn[i] = ob[i]
    toReturn

module.exports = new ComponentManager