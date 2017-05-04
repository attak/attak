AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Permissions extends BaseComponent
  namespace: 'permissions'
  platforms: ['AWS']
  simulation:
    services: [
      'AWS:Lambda'
      'AWS:Gateway'
    ]

  create: (path, newDefs, opts) ->
    # Creating a new name is a noop
    []

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'Remove name'
        run: (done) ->
          console.log "REMOVING NAME", path[0], oldDefs
          done()
      }
    ]

module.exports = Permissions