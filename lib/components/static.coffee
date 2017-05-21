AWS = require 'aws-sdk'
async = require 'async'
extend = require 'extend'
AWSUtils = require '../aws'
BaseComponent = require './base_component'

class Static extends BaseComponent
  namespace: 'static'
  dependencies: ['name']

  create: (path, newDefs, opts) ->
    # Creating a new name is a noop
    [
      msg: 'setup static hosting'
      run: (state, done) ->
        console.log "CREATE STATIC HOSTING", path, newDefs, state
        [namespace, args...] = path
        [staticName, staticArgs...] = args

        state.static = extend true, state.static,
          "#{staticName}": newDefs

        console.log "STATE BEFORE STATIC", state
        AWSUtils.setupStatic state, staticName, opts, (err, results) ->
          console.log "SETUP STATIC RESULTS"
          done err, state
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'remove static hosting'
        run: (state, done) ->
          console.log "REMOVING STATIC HOSTING", path[0], oldDefs
          done null, state
      }
    ]

module.exports = Static