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

  notifyChange: (path, plan, oldState, newState, diffs, opts, callback) ->
    response =
      handle: (component, params, plan) =>
        component.planResolution oldState, newState, diffs, opts, (err, newPlan) ->
          console.log "NOTIFY RESPONSE", err, newPlan
          callback null, [plan..., newPlan...]

    request =
      method: 'POST'
      body:
        plan: plan
        path: path
        oldState: oldState
        newState: newState
      url: "/#{path.join '/'}"

    @router.handle request, response, (err) ->
      console.log "NOTIFY RESPONSE", err
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