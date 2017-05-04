AWS = require 'aws-sdk'
uuid= require 'uuid'
async = require 'async'
extend = require 'extend'
moment = require 'moment'
AWSUtils = require '../aws'
AttakProc = require 'attak-processor'
Permissions = require './permissions'
TopologyUtils = require '../topology'
BaseComponent = require './base_component'

class Streams extends BaseComponent
  namespace: 'streams'
  platforms: ['AWS']
  dependencies: [
    'name'
    'processors/:processorName'
  ]
      # deploy: (oldState, newState, processorName) ->
      #   for stream, defs of newState.streams
      #     if newState.processors[stream.to] is processorName or newState.processors[stream.from] is processorName
      #       return true
      #   return false

  structure:
    ':streamName':
      to: '/processors/:processorName/*'
      from: '/processors/:processorName/*'
      topic: 'string'

  simulation:
    services: ->
      'AWS:Kinesis':
        handlers:
          "POST /": @handleKinesisPut

  init: (callback) ->
    @children = 
      permissions: new Permissions extend @options,
        path: [@path..., 'permissions']
    callback()

  create: (path, defs, opts) ->
    [namespace, name, args...] = path
    [
      {
        msg: "Create new stream"
        run: (done) =>
          if namespace is 'processors'
            addedState =
              streams: {}
            
            for streamName, stream of opts.target.streams
              if stream.to is name or stream.from is name
                addedState.streams[streamName] =
                  id: uuid.v1()

            modifiedTarget = extend true, opts.target, addedState
            done null, modifiedTarget
          else
            done null
          # @createStream streamName, defs, opts, (err, results) ->
          #   defs = extend defs,
          #     id: uuid.v1()
          #   console.log "MODIFIED STREAM DEFS", defs
          #   done err, defs
      }
    ]

  delete: (path, defs, opts) ->
    [
      {
        msg: "Remove stream"
        run: (done) ->
          console.log "REMOVING STREAM", path[0], defs
          done()
      }
    ]

  createStream: (streamName, defs, opts, callback) ->
    console.log "CREATING NEW STREAM", streamName, defs, opts
    AWSUtils.createStream opts, opts.dependencies.name, streamName, (err, results) ->
      AWSUtils.describeStream opts, opts.dependencies.name, streamName, (err, streamResults) ->
        targetProcessor = opts.dependencies.processors["#{defs.to}-#{opts.environment}"]
        AWSUtils.associateStream opts, streamResults.StreamDescription, targetProcessor, (err, results) ->
          callback()

  invokeProcessor: (processorName, data, state, opts, callback) ->
    context =
      done: -> callback()
      fail: (err) -> callback err
      success: (results) -> callback null, results
      state: state

    processor = TopologyUtils.getProcessor opts, state, processorName
    handler = AttakProc.handler processorName, state, processor, opts
    handler data, context, (err, results) ->
      callback err, results

  getTargetProcessor: (state, targetStream) ->
    for streamName, stream of (state.streams || {})
      streamName = AWSUtils.getStreamName state.name, stream.from, stream.to
      console.log "STREAM NAME", streamName, "LOOKING FOR", targetStream
      if streamName is targetStream
        return stream.to

  handleKinesisPut: (state, opts, req, res) =>
    console.log "HANDLE KINESIS PUT", req.body, req.headers

    targetId = req.headers['x-amz-target']
    [version, type] = targetId.split '.'

    streamExists = false
    for streamName, stream of (state.streams || {})
      if AWSUtils.getStreamName(state.name, stream.from, stream.to) is req.body.StreamName
        streamExists = true

    switch type
      when 'CreateStream'
        console.log "CREATE STREAM", req.body

        if streamExists
          res.status 502
          res.header 'x-amzn-errortype', 'ResourceInUseException'
          res.json
            message: "Stream already exists with name #{req.body.StreamName}"
        else
          res.send 200
      when 'DescribeStream'
        if streamExists
          res.json
            StreamDescription:
              StreamARN: "arn:aws:kinesis:us-east-1:133713371337:stream/#{req.body.StreamName}"
              StreamName: req.body.StreamName
              StreamStatus: 'ACTIVE'
              Shards: [{
                ShardId: 'shardId-000000000000'
                HashKeyRange:
                  StartingHashKey: '0'
                  EndingHashKey: '340282366920938463463374607431768211455'
                SequenceNumberRange: 'StartingSequenceNumber': '49571707312524580937567729167305629757076706705499226114'
              }]
              HasMoreShards: false
              RetentionPeriodHours: 24
              StreamCreationTimestamp: moment().format()
              EnhancedMonitoring: [{'ShardLevelMetrics': []}]
        else
          res.status 400
          res.header 'x-amzn-errortype', 'ResourceNotFoundException'
          res.json
            message: "Stream not found: #{req.body.StreamName}"
      else
        console.log "GOT STREAM PUT", targetId, req.body

        if streamExists
          processorName = @getTargetProcessor state, req.body.StreamName
          data = JSON.parse new Buffer(req.body.Data, 'base64').toString()
          @invokeProcessor processorName, data.data, state, opts, (err, results) ->
            res.json {ok: true}
        else
          res.status 400
          res.header 'x-amzn-errortype', 'ResourceNotFoundException'
          res.json
            message: "Stream not found: #{req.body.StreamName}"

module.exports = Streams