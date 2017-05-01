AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Name extends BaseComponent
  namespace: 'name'
  required: true

  create: (path, newDefs, callback) ->
    # Creating a new name is a noop
    callback null

  delete: (path, oldDefs, callback) ->
    console.log "REMOVING NAME", path[0], oldDefs
    callback null

module.exports = Name