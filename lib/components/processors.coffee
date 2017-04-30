AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Processors extends BaseComponent
  platforms: ['AWS']
  services:
    AWS: ['lambda']

  getState: (callback) ->
    state = {}

    lambda = new AWS.Lambda
      region: @options.region || 'us-east-1'

    @getAllFunctions lambda, (err, functions) =>
      if err then return callback(err)

      for fn in functions
        if fn.Environment?.Variables?.ATTAK_TOPOLOGY_NAME is @options.topology.name
          state[fn.Environment.Variables.ATTAK_PROCESSOR_NAME] = fn

      callback err, state

  getAllFunctions: (lambda, callback) ->
    marker = undefined
    functions = []
    
    async.doWhilst (done) ->
      params =
        MaxItems: 200
        Marker: marker

      lambda.listFunctions params, (err, results) ->
        if err then return done(err)
        
        marker = results.NextMarker
        for data in results.Functions
          functions.push data
    , () ->
      marker?
    , (err, numPages) ->
      callback err, functions

  create: (path, newDefs, callback) ->
    console.log "CREATING NEW PROCESSOR", path[0], newDefs
    callback null

  update: (path, oldDefs, newDefs, callback) ->
    console.log "UPDATING PROCESSOR", path[0], oldDefs, newDefs
    callback null

  delete: (path, oldDefs, callback) ->
    console.log "REMOVING PROCESSOR", path[0], oldDefs
    callback null
module.exports = Processors