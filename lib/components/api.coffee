AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class API extends BaseComponent
  namespace: 'api'
  platforms: ['AWS']
  simulation:
    services: [
      'AWS:Lambda'
      'AWS:APIGateway'
    ]

  create: (path, newDefs, callback) ->
    [
      {
        msg: 'Create new API'
        run: (done) ->
          console.log "CREATING NEW API", newDefs
          done()
      }
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'Remove API'
        run: (done) ->
          console.log "REMOVING API", path[0], oldDefs
          done()
      }
    ]

module.exports = API