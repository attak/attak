AWS = require 'aws-sdk'
async = require 'async'
LambdaUtils = require '../lambda'
BaseComponent = require './base_component'
SimulationUtils = require '../simulation/simulation'

class Processors extends BaseComponent
  namespace: 'processors'
  platforms: ['AWS']
  dependencies: ['name']
  simulation:
    services: ->
      'AWS:API':
        handlers:
          "POST /:apiVerison/functions/:functionName/invoke-async": @handleInvoke
          "GET /:apiVerison/functions/:functionName": @handleGetFunction

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

  # create: (path, newDefs, opts) ->
  resolveState: (currentState, newState, diffs, opts, callback) ->
    opts =
      name: opts.dependencies.name
      services: opts.services
      processors: newState

    LambdaUtils.deployProcessors opts, (err, results) ->
      console.log "DONE DEPLOY", err, results
      callback err

  update: (path, oldDefs, newDefs, opts) ->
    console.log "UPDATING PROCESSOR", path[0], oldDefs, newDefs
    @state[path[0]] = newDefs
    callback null

  delete: (path, oldDefs, opts) ->
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

  handleGetFunction: (state, opts, req, res) ->
    console.log "HANDLING REQUEST", opts, req.method, req.url, req.params
    name = req.params.functionName

    if state.processors?[name] is undefined
      console.log "404 FUNCTION NOT FOUND"
      res.status 400
      res.header 'x-amzn-errortype', 'ResourceNotFoundException'
      res.json
        message: "Function not found: arn:aws:lambda:us-east-1:133713371337:function:#{name}"
        code: 'ResourceNotFoundException'
    else
      res.json
        Configuration: 
          FunctionName: 'lamprey-production'
          FunctionArn: 'arn:aws:lambda:us-east-1:133713371337:function:lamprey-production'
          Runtime: 'nodejs4.3'
          Role: 'arn:aws:iam::133713371337:role/lambda'
          Handler: 'attak_runner.handler'
          CodeSize: 5245616
          Description: ''
          Timeout: 3
          MemorySize: 512
          LastModified: '2016-06-13T05:08:43.436+0000'
          CodeSha256: 'fEHreHoyS2q8/9dttxsvO/YlHBJ0YMDR6HYhMTlpylo='
          Version: '$LATEST'
          KMSKeyArn: null
          TracingConfig:
            Mode: 'PassThrough'
        Code: 
          RepositoryType: 'S3'
          Location: "https://prod-04-2014-tasks.s3.amazonaws.com/snapshots/133713371337/#{name}-#{uuid.v1()}"

module.exports = Processors