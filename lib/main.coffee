fs = require 'fs'
uuid = require 'uuid'
chalk = require 'chalk'
async = require 'async'
nodePath = require 'path'
AWSUtils = require './aws'
inquirer = require 'inquirer'
download = require 'download-github-repo'
CommUtils = require './comm'
kinesalite = require 'kinesalite'
LambdaUtils = require './lambda'

process.on 'uncaughtExcepction', (err) ->
  console.log "UNCAUGHT", err

Attak =
  __internal:
    version: '0.0.1'
    aws: AWSUtils
    comm: CommUtils
    lambda: LambdaUtils

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
    workingDir = program.cwd || process.cwd()
    topology = program.topology || require workingDir

    program.startTime = new Date

    if topology.processors.constructor is String
      processorPath = nodePath.resolve(workingDir, topology.processors)
      console.log "PROCESSOR PATH", processorPath
      files = fs.readdirSync processorPath
      
      processors = {}
      for file in files
        if file is '.DS_Store'
          continue
        name = nodePath.basename file, nodePath.extname(file)
        processors[name] = "#{topology.processors}/#{file}"

      topology.processors = processors

    inputPath = nodePath.resolve (program.cwd || process.cwd()), program.inputFile
    input = topology.input || require inputPath

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

            opts =
              report: wrtc.emit

            Attak.runSimulations program, topology, input, opts, callback

        else
          Attak.runSimulations program, topology, input, {}, callback

  runSimulations: (program, topology, input, simOpts, callback) ->
    allResults = {}
    async.eachOf input, (data, processor, next) ->
      
      runSimulation = (procName, simData, isTopLevel=true) ->
        numEmitted = 0
        try
          AWSUtils.simulate program, topology, procName, simData, (topic, emitData, opts) ->

            numEmitted += 1
            report = program.report || simOpts?.report || (eventName, args...) ->
              console.log chalk.blue("#{procName} : #{topic}", JSON.stringify(emitData))

            report 'emit',
              data: emitData
              topic: topic       
              trace: numEmitted #simData.trace || uuid.v1()
              processor: procName
            
            if allResults[procName] is undefined
              allResults[procName] = {}
            allResults[procName][topic] = emitData
            for stream in topology.streams
              if stream.from is procName and (stream.topic || topic) is topic
                runSimulation stream.to, emitData, false
          
          , (err, results) ->
            if isTopLevel
              console.log "CALLING NEXT", err, results
              next()
        catch e
          console.log "Error running #{procName}:\n#{e} #{e.stack}"

      runSimulation processor, data
    , (err) ->
      callback? err, allResults

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