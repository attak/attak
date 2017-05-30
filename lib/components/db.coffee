AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class DB extends BaseComponent
  namespace: 'db'
  dependencies: ['name']

  simulation:
    services: ->
      'AWS:DynamoDB': {}

  create: (path, newDefs, opts) -> []
  delete: (path, oldDefs, callback) -> []

module.exports = DB