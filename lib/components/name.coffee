AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Name extends BaseComponent
  namespace: 'name'
  required: true

  create: (path, newDefs, opts) ->
    # Creating a new name is a noop
    [
      msg: 'setup name'
      run: (state, done) ->
        console.log "CREATE NAME"
        state.name = newDefs
        done null, state
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'Remove name'
        run: (state, done) ->
          console.log "REMOVING NAME", path[0], oldDefs
          delete state.name
          done null, state
      }
    ]

module.exports = Name