fs = require 'fs'
AWS = require 'aws-sdk'
async = require 'async'
extend = require 'extend'
nodePath = require 'path'
AWSUtils = require '../aws'
staticHost = require 'node-static'
BaseComponent = require './base_component'

class Static extends BaseComponent
  namespace: 'static'
  dependencies: ['name']

  simulation:
    services: ->
      'ATTAK:Static':
        handlers:
          'GET /:staticName': @handleRequest
          'GET /:staticName/*': @handleRequest

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

        AWSUtils.setupStatic state, staticName, opts, (err, results) ->
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

  handleRequest: (state, opts, req, res) ->
    staticName = req.params.staticName || 'default'

    path = req.url.split("/#{staticName}")[1]
    workingDir = opts.workingDir || process.cwd()
    console.log "HANDLE STATIC FILE REQUEST", path
    console.log "WHAT IS STATE", staticName, state.static[staticName].dir, state

    staticDir = nodePath.resolve workingDir, state.static[staticName].dir
    fullPath = "#{staticDir}/#{path}"

    stream = fs.createReadStream fullPath
    stream.pipe res

module.exports = Static