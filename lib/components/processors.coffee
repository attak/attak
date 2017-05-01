AWS = require 'aws-sdk'
async = require 'async'
BaseComponent = require './base_component'
SimulationUtils = require '../simulation/simulation'

class Processors extends BaseComponent
  namespace: 'processors'
  platforms: ['AWS']
  simulation:
    services: ->
      'AWS:API':
        handlers:
          "POST /:apiVerison/functions/:functionName/invoke-async": @handleInvoke

  fetchState: (callback) ->
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

        done()
    , () ->
      marker?
    , (err, numPages) ->
      callback err, functions

  create: (path, newDefs, callback) ->
    [
      {
        msg: "Create new processor #{path[0]}"
        run: (done) ->
          console.log "CREATING NEW PROCESSOR", path[0], newDefs
          done()
      }
    ]

  update: (path, oldDefs, newDefs, callback) ->
    console.log "UPDATING PROCESSOR", path[0], oldDefs, newDefs
    @state[path[0]] = newDefs
    callback null

  delete: (path, oldDefs, callback) ->
    console.log "REMOVING PROCESSOR", path[0], oldDefs
    delete @state[path[0]]
    callback null

  handleInvoke: (topology, opts, req, res) ->
    environment = opts.environment || 'development'

    splitPath = req.url.split '/'
    fullName = splitPath[3]
    functionName = fullName.split("-#{environment}")[0]

    event =
      path: req.url
      body: body
      headers: req.headers
      httpMethod: req.method
      queryStringParameters: req.query

    SimulationUtils.runSimulation allResults, opts, topology, simOpts, event, functionName, ->
      if allResults[functionName]?.callback.err
        res.writeHead 500
        return res.end allResults[functionName]?.callback.err.stack

      response = allResults[functionName]?.callback?.results?.body || ''
      if not response
        return res.end()

      try
        respData = JSON.parse response
        if respData.status or respData.httpStatus or respData.headers
          res.writeHead (respData.status || respData.httpStatus || 200), respData.headers
        res.end respData
      catch e
        res.end response

module.exports = Processors