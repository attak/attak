AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class API extends BaseComponent
  platforms: ['AWS']
  simulation:
    services: [
      ['AWS', 'lambda']
      ['AWS', 'gateway']
    ]

  getState: (callback) ->
    callback null, @state

  create: (path, newDefs, callback) ->
    console.log "CREATING NEW API", newDefs
    @state[path[0]] = newDefs
    callback null

  delete: (path, oldDefs, callback) ->
    console.log "REMOVING API", path[0], oldDefs
    callback null

module.exports = API