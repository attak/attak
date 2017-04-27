AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'

class Processors extends BaseComponent
  platforms: ['AWS']
  services:
    AWS: ['lambda']

  getState: (callback) ->
    lambda = new AWS.Lambda
      region: @options.region || 'us-east-1'

    Processors.getAllFunctions lambda, (err, functions) ->
      if err then return callback(err)



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

module.exports = Processors