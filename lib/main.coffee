fs = require 'fs'
async = require 'async'
nodePath = require 'path'
AWSUtils = require './aws'
inquirer = require 'inquirer'
download = require 'download-github-repo'
CommUtils = require './comm'
LambdaUtils = require './lambda'
TopologyUtils = require './topology'
SimulationUtils = require './simulation'

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

  simulate: (program, callback) ->
    topology = TopologyUtils.loadTopology program

    program.startTime = new Date
    program.environment = program.environment || 'development'

    if program.input
      input = program.input
    else
      inputPath = nodePath.resolve (program.cwd || process.cwd()), program.inputFile
      if fs.existsSync inputPath
        input = require inputPath
      else
        input = undefined

    if program.id
      CommUtils.connect program, (socket, wrtc) ->
        wrtc.emit 'topology',
          topology: topology

        emitter = wrtc.emit
        wrtc.reconnect = (wrtc) ->
          emitter = wrtc.emit

        opts =
          report: () ->
            emitter? arguments...

        SimulationUtils.runSimulations program, topology, input, opts, callback

    else
      SimulationUtils.runSimulations program, topology, input, {}, callback

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

    LambdaUtils.deployProcessors topology, opts, (err, lambdas) ->
      AWSUtils.deployStreams topology, opts, lambdas, (err, streams) ->
        gateway = undefined
        async.parallel [
          (done) ->
            if topology.api
              gatewayOpts =
                name: "#{topology.name}-#{opts.environment || 'development'}"
                environment: opts.environment

              AWSUtils.setupGateway topology.api, gatewayOpts, (err, results) ->
                gateway = results
                done err
            else
              done()
          (done) ->
            if topology.schedule
              AWSUtils.setupSchedule topology, opts, (err, results) ->
                done err
            else
              done()
          (done) ->
            if topology.static
              AWSUtils.setupStatic topology, opts, (err, results) ->
                done err
            else
              done()
        ], (err) ->
          if topology.provision
            config =
              aws:
                endpoints: {}

            topology.provision topology, config, (err) ->
              callback err, {'lambdas', 'streams', gateway}
          else
            callback? err, {lambdas, streams, gateway}

module.exports = Attak