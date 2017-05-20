fs = require 'fs'
async = require 'async'
ATTAK = require './attak'
nodePath = require 'path'
AWSUtils = require './aws'
inquirer = require 'inquirer'
download = require 'download-github-repo'
CommUtils = require './comm'
LambdaUtils = require './lambda'
TopologyUtils = require './topology'
ServiceManager = require './simulation/service_manager'
SimulationUtils = require './simulation/simulation'

Attak =
  utils:
    aws: AWSUtils
    comm: CommUtils
    lambda: LambdaUtils
    topology: TopologyUtils
    simulation: SimulationUtils

  init: (program, callback) ->
    console.log "INIT"
    workingDir = program.cwd || process.cwd()

    questions = [{
      type: 'input',
      name: 'name',
      message: 'Project name?'
      default: 'attak-hello-world'
    }]

    inquirer.prompt questions
      .then (answers) ->
        path = "#{workingDir}/#{answers.name}"
        console.log "FULL PATH", path
        
        if not fs.existsSync path
          fs.mkdirSync path

        download "attak/attak-hello-world", path, ->
          console.log "DONE", arguments
          callback()
      .catch (err) ->
        console.log "CAUGHT ERROR", err

  trigger: (program, callback) ->
    topology = require (program.cwd || process.cwd())
    inputPath = nodePath.resolve (program.cwd || process.cwd()), program.inputFile
    input = topology.input || require inputPath

    program.startTime = new Date

    async.eachOf input, (data, processor, next) ->      
      AWSUtils.triggerProcessor program, processor, data, (err, results) ->
        next()
    , (err) ->
      async.eachOf topology.processors, (procData, procName, nextProc) ->
        AWSUtils.monitorLogs program, procName, (err, results) ->
          nextProc()
      , ->
        callback? err

  deploy: (opts, callback) ->
    topology = TopologyUtils.loadTopology opts

    opts.startTime = new Date
    opts.environment = opts.environment || 'development'

    input = {}
    if opts.input
      input = opts.input
    else if opts.inputFile
      inputPath = nodePath.resolve (opts.cwd || process.cwd()), opts.inputFile
      if fs.existsSync inputPath
        input = require inputPath

    app = new ATTAK
      topology: topology
      simulation: opts.simulation
      environment: opts.environment

    app.clearState()
    app.setup ->
      services = app.getSimulationServices()

      manager = new ServiceManager
        app: app

      manager.setup topology, opts, services, (err, services) ->
        opts.services = services
        app.setState opts.startState || {}, topology, opts, (err, results) ->
          if err then return callback err
          async.forEachOf input, (data, processorName, nextProcessor) ->
            lambda = new AWS.Lambda
              region: 'us-east-1'
              endpoint: services['AWS:API']

            params = 
              InvokeArgs: new Buffer JSON.stringify(data)
              FunctionName: "#{processorName}-#{opts.environment || 'development'}"

            lambda.invokeAsync params
              .on 'build', (req) ->
                req.httpRequest.endpoint.host = services['AWS:API'].host
                req.httpRequest.endpoint.port = services['AWS:API'].port
              .send (err, data) ->
                console.log "INVOKE RESULTS", err, data
                nextProcessor err
          , (err) ->
            callback err

module.exports = Attak