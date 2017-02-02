async = require 'async'
nodePath = require 'path'
AWSUtils = require './aws'
LambdaUtils = require './lambda'

module.exports =
  version: '0.0.1'

  simulate: (program) ->
    topology = require process.cwd()
    inputPath = nodePath.resolve process.cwd(), program.inputFile
    input = topology.input || require inputPath

    async.eachOf input, (data, processor, next) ->      
      AWSUtils.simulate program, topology, processor, data, (err, results) ->
        next()
    , ->

  trigger: (program) ->
    topology = require process.cwd()
    inputPath = nodePath.resolve process.cwd(), program.inputFile
    input = topology.input || require inputPath

    async.eachOf input, (data, processor, next) ->
      console.log "TRIGGERING", processor, data
      
      AWSUtils.triggerProcessor program, processor, data, (err, results) ->
        next()
    , ->
      console.log "DONE TRIGGERING"

  deploy: (program) ->
    topology = require process.cwd()

    if topology.name is undefined
      throw new Error 'topology.name is undefined'

    console.log "DEPLOY", topology

    LambdaUtils.deployProcessors topology, program, (err, lambdas) ->
      AWSUtils.deployStreams topology, program, lambdas, (err, streams) ->
        console.log "DONE WITH EVERYTHING"