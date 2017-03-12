fs = require 'fs'
async = require 'async'
nodePath = require 'path'
AWSUtils = require './aws'
inquirer = require 'inquirer'
download = require 'download-github-repo'
CommUtils = require './comm'
kinesalite = require 'kinesalite'
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

    if program.input
      input = program.input
    else
      inputPath = nodePath.resolve (program.cwd || process.cwd()), program.inputFile
      input = require inputPath

    kinesaliteServer = kinesalite
      # ssl: true
      path: nodePath.resolve __dirname, '../simulationdb'
      createStreamMs: 0

    kinesaliteServer.listen 6668, (err) ->
      program.kinesisEndpoint = 'http://localhost:6668'

      AWSUtils.deploySimulationStreams program, topology, (streamNames) ->
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

  deploy: (program, callback) ->
    topology = require (program.cwd || process.cwd())

    if topology.name is undefined
      throw new Error 'topology.name is undefined'

    LambdaUtils.deployProcessors topology, program, (err, lambdas) ->
      AWSUtils.deployStreams topology, program, lambdas, (err, streams) ->
        callback? err, {lambdas, streams}

module.exports = Attak