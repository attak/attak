AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Hooks extends BaseComponent
  namespace: 'hooks'

  structure:
    ':hookName':
      handler: '*'

  create: (path, newDefs, opts) ->
    console.log "GOT create", path, newDefs
    [
      {
        msg: 'setup state change hooks'
        run: (state, done) ->
      }
    ]

  delete: (path, oldDefs, opts) ->
    console.log "GOT delete", path, newDefs
    []

module.exports = Hooks