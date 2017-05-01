AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class API extends BaseComponent
  namespace: 'api'
  platforms: ['AWS']
  simulation:
    services: [
      'AWS:Lambda'
      'AWS:Gateway'
    ]

  create: (path, newDefs, callback) ->
    console.log "CREATING NEW API", newDefs
    @state[path[0]] = newDefs
    callback null

  delete: (path, oldDefs, callback) ->
    if path[0] is undefined
      return callback null
    
    console.log "REMOVING API", path[0], oldDefs
    callback null

module.exports = API