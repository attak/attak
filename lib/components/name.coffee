AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Name extends BaseComponent
  namespace: 'name'
  required: true

  create: (path, newDefs, opts) ->
    # Creating a new name is a noop
    []

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'Remove name'
        run: (state, done) ->
          console.log "REMOVING NAME", path[0], oldDefs
          done()
      }
    ]

module.exports = Name