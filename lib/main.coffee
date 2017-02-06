chalk = require 'chalk'
async = require 'async'
nodePath = require 'path'
AWSUtils = require './aws'
LambdaUtils = require './lambda'

module.exports =
  version: '0.0.1'

  simulate: (program, callback) ->
    topology = program.topology || require (program.cwd || process.cwd())
    inputPath = nodePath.resolve (program.cwd || process.cwd()), program.inputFile
    input = topology.input || require inputPath

    allResults = {}

    async.eachOf input, (data, processor, next) ->
      runSimulation = (procName, simData, isTopLevel=true) ->
        AWSUtils.simulate program, topology, procName, simData, (topic, emitData, opts) ->
          report = program.report || console.log
          report chalk.blue("#{procName} : #{topic} -> #{JSON.stringify(emitData)}")
          
          if allResults[procName] is undefined
            allResults[procName] = {}
          allResults[procName][topic] = emitData
          for stream in topology.streams
            if stream.from is procName and (stream.topic || topic) is topic
              runSimulation stream.to, emitData, false
        
        , (err, results) ->
          if isTopLevel
            next()

      runSimulation processor, data
    , (err) ->
      callback? err, allResults

  trigger: (program, callback) ->
    topology = require (program.cwd || process.cwd())
    inputPath = nodePath.resolve (program.cwd || process.cwd()), program.inputFile
    input = topology.input || require inputPath

    async.eachOf input, (data, processor, next) ->      
      AWSUtils.triggerProcessor program, processor, data, (err, results) ->
        next()
    , ->
      callback? err, results

  deploy: (program, callback) ->
    topology = require (program.cwd || process.cwd())

    if topology.name is undefined
      throw new Error 'topology.name is undefined'

    LambdaUtils.deployProcessors topology, program, (err, lambdas) ->
      AWSUtils.deployStreams topology, program, lambdas, (err, streams) ->
        callback? err, results