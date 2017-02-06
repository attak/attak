async = require 'async'
nodePath = require 'path'
AWSUtils = require './aws'
LambdaUtils = require './lambda'

module.exports =
  version: '0.0.1'

  simulate: (program, callback) ->
    topology = program.topology || require process.cwd()
    inputPath = nodePath.resolve process.cwd(), program.inputFile
    input = topology.input || require inputPath

    if topology.processor
      program.processor = topology.processor

    allResults = []

    async.eachOf input, (data, processor, next) ->      
      AWSUtils.simulate program, topology, processor, data, (err, results) ->
        allResults.push results
        next()
    , (err) ->
      callback? err, results

  trigger: (program, callback) ->
    topology = require process.cwd()
    inputPath = nodePath.resolve process.cwd(), program.inputFile
    input = topology.input || require inputPath

    async.eachOf input, (data, processor, next) ->
      console.log "TRIGGERING", processor, data
      
      AWSUtils.triggerProcessor program, processor, data, (err, results) ->
        next()
    , ->
      callback? err, results

  deploy: (program, callback) ->
    topology = require process.cwd()

    if topology.name is undefined
      throw new Error 'topology.name is undefined'

    console.log "DEPLOY", topology

    LambdaUtils.deployProcessors topology, program, (err, lambdas) ->
      AWSUtils.deployStreams topology, program, lambdas, (err, streams) ->
        callback? err, results