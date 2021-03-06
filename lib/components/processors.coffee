AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
moment = require 'moment'
extend = require 'extend'
AWSUtils = require '../aws'
AttakProc = require 'attak-processor'
LambdaUtils = require '../lambda'
BaseComponent = require './base_component'
TopologyUtils = require '../topology'
SimulationUtils = require '../simulation/simulation'

class Processors extends BaseComponent
  namespace: 'processors'
  platforms: ['AWS']
  dependencies: ['name']
  simulation:
    services: ->
      'AWS:Lambda':
        handlers:
          "POST /:apiVerison/functions/:functionName/invoke-async": @handleInvoke
          "POST /:apiVerison/functions/:functionName/invocations": @handleInvoke
          "DELETE /:apiVerison/functions/:functionName": @handleDeleteFunction
          "GET /:apiVerison/functions/:functionName": @handleGetFunction
          "POST /:apiVerison/functions": @handleCreateFunction
          "PUT /:apiVerison/functions": @handleCreateFunction

  structure:
    ':processorName':
      id: 'id'
      name: '/name'

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

  handleNameChange: (state, newName, opts, callback) ->
    if Object.keys(state.processors || {}).length > 0      
      oldProcessors = extend true, {}, state.processors

      processorList = Object.keys(state.processors)
      @removeProcessors state, processorList, newName, opts, (err) =>
        @createProcessors state, oldProcessors, opts, (err, addedState) ->
          callback err, addedState
    else
      callback null, {}

  removeProcessors: (state, processorList, newState, opts, callback) ->
    AWSUtils.removeProcessors state.name, processorList, opts, (err, results) ->
      for processor in processorList
        delete state.processors[processor]
      callback err

  createProcessors: (state, newState, opts, callback) ->
    deployOpts = extend true, {}, opts
    deployOpts = extend true, deployOpts,
      name: state.name
      services: opts.services
      processors: newState

    LambdaUtils.deployProcessors state, deployOpts, (err, procDatas) ->
      addedState =
        processors: {}
      
      for funcName, procData of procDatas
        [err, results] = procData

        if err
          console.log "PROC DATA ERR", funcName, err, results

        environment = opts.environment || 'development'
        extendedProcName = funcName.split("-#{environment}")[0]
        procName = extendedProcName.split("#{state.name}-")[1]
        addedState.processors[procName] =
          id: results.FunctionArn

      callback err, addedState

  handleDiffs: (currentState, newState, diffs=[], opts) ->
    [
      msg: 'resolve processor state'
      run: (state, done) =>

        async.each diffs, (diff, nextDiff) =>
          switch diff.path[0]
            when 'name'
              @handleNameChange state, newState, opts, (err, addedState) ->
                if err then return nextDiff err
                state = extend true, state, addedState
                nextDiff()
            when 'processors'
              @createProcessors state, newState, opts, (err, addedState) ->
                if err then return nextDiff err
                state = extend true, state, addedState
                nextDiff()

            else
              err = new Error "UNKNOWN PROCESSOR CHANGE PATH", dif
              nextDiff err
        , (err) ->
          done err, state
    ]

  handleInvoke: (state, opts, req, res) =>
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', =>
      data = JSON.parse allData    

      environment = opts.environment || 'development'

      splitPath = req.url.split '/'
      fullName = splitPath[3]
      extendedName = fullName.split("-#{environment}")[0]
      processorName = extendedName.split("#{state.name}-")[1]
      @invokeProcessor processorName, fullName, data, state, opts, (err, results) ->
        if err
          res.status(500).send err
        else
          res.end results.body

  invokeProcessor: (processorName, fullName, data, state, opts, callback) ->
    topology = TopologyUtils.loadTopology opts

    services = {}
    for serviceKey, service of opts.services
      services[serviceKey] =
        endpoint: service.endpoint 
    
    context =
      done: -> callback()
      fail: (err) -> callback err
      success: (results) -> callback null, results
      state: state
      topology: topology
      services: services
      functionName: fullName

    {impl} = TopologyUtils.getProcessor opts, topology, processorName
    handler = AttakProc.handler processorName, topology, impl, opts
    handler data, context, (err, results) ->
      callback err, results

  handleCreateFunction: (state, opts, req, res) ->
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', ->
      data = JSON.parse allData

      name = data.FunctionName
      res.json
        FunctionName: name
        FunctionArn: "arn:aws:lambda:us-east-1:133713371337:function:#{name}"
        Runtime: 'nodejs4.3'
        Role: 'arn:aws:iam::133713371337:role/lambda'
        CodeSize: 8469826
        Version: '$LATEST'
        TracingConfig: Mode: 'PassThrough'

  handleDeleteFunction: (state, opts, req, res) ->
    res.end()

  handleGetFunction: (state, opts, req, res) ->
    name = req.params.functionName

    if state.processors?[name] is undefined
      res.status 400
      res.header 'x-amzn-errortype', 'ResourceNotFoundException'
      res.json
        message: "Function not found: arn:aws:lambda:us-east-1:133713371337:function:#{name}"
        code: 'ResourceNotFoundException'
    else
      res.json
        Configuration:
          FunctionName: name
          FunctionArn: "arn:aws:lambda:us-east-1:133713371337:function:#{name}"
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