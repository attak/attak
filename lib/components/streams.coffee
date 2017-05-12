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

  structure:
    ':streamName':
      id: 'string'
      to: '/processors/:processorName/*'
      from: '/processors/:processorName/*'
      topic: 'string'

  simulation:
    services: ->
      'AWS:Kinesis':
        handlers:
          "POST /": @handleKinesisPut
      'AWS:Lambda':
        handlers:
          "POST /:apiVerison/event-source-mappings": @handleCreateEventSourceMapping

  init: (callback) ->
    callback()

  getProcessorStreams: (state, processorName) ->
    streams = []
    for thisName, stream of (state.streams || {})
      if stream.to is name or stream.from is name
        streams.push [thisName, stream]
    streams

  create: (path, defs, opts) ->
    [namespace, args...] = path

    [
      {
        msg: "Create new stream"
        run: (state, done) =>
          console.log "RUN CREATE STREAMS", path, defs, state
          if namespace is 'processors'
            [procName, procArgs...] = args
            streams = @getProcessorStreams state, procName
            async.eachSeries streams, ([streamName, streamDefs], nextStream) ->
              @createStream state, streamName, defs, opts, (err, streamData, association) ->
                if err then return done err
                state.streams[streamData.StreamDescription.StreamName].id = streamData.StreamDescription.StreamARN
                nextStream err
            , (err) ->
              done err, state
          else if namespace is 'streams'
            [streamName, streamDefs] = args
            @createStream state, streamName, defs, opts, (err, streamData, association) ->
              if err then return done err
              extendedState = extend state,
                "#{streamData.StreamDescription.StreamName}":
                  id: streamData.StreamDescription.StreamARN
              done err, extendedState
      }
    ]

  delete: (path, defs, opts) ->
    [
      {
        msg: "Remove stream"
        run: (state, done) ->
          console.log "REMOVING STREAM", path[0], defs
          done()
      }
    ]

  createStream: (state, streamName, defs, opts, callback) ->
    console.log "ACTUAL CREATE STREAM", streamName, defs, state
    AWSUtils.createStream opts, state.name, streamName, (err, results) ->
      AWSUtils.describeStream opts, state.name, streamName, (err, streamResults) ->
        if err then return callback err
        console.log "DESCRIBE STREAM DONE", err, streamResults, state
        targetProcessor = extend true, {}, state.processors[defs.to]
        targetProcessor.name = defs.to

        streamDefs =
          id: streamResults.StreamDescription.StreamARN

        AWSUtils.associateStream state, streamDefs, targetProcessor, opts, (err, associationResults) ->
          callback err, streamResults, associationResults

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

  handleKinesisPut: (state, opts, req, res, done) =>
    targetId = req.headers['x-amz-target']
    [version, type] = targetId.split '.'

    if state.name is undefined and state.processors
      for procName, procDefs of state.processors
        [thisStateName, otherProc] = req.body.StreamName.split("-#{procName}-")
        console.log "LOOKING AT", procName, thisStateName, otherProc, state.processors?[otherProc]?
        if otherProc and state.processors?[otherProc] isnt undefined
          stateName = thisStateName
          break
    else
      stateName = state.name

    streamDefs = undefined
    for streamName, stream of (state.streams || {})
      thisStream = AWSUtils.getStreamName(stateName, stream.from, stream.to)
      console.log "EXAMINING", req.body.StreamName, thisStream, stateName, stream
      if thisStream is req.body.StreamName
        streamDefs = [streamName, stream]
      else
        console.log "NO MATCH", req.body.StreamName, thisStream, stream

    console.log "HANDLE KINESIS PUT", type, streamDefs, req.body

    switch type
      when 'CreateStream'
        console.log "CREATE STREAM", req.body, state, streamDefs

        if streamDefs
          res.header 'x-amzn-errortype', 'ResourceInUseException'
          res.json
            message: "Stream already exists with name #{req.body.StreamName}"
        else
          console.log "STREAMS ARE", req.body.StreamName, Object.keys(state.streams || {}), state

          if state.streams is undefined
            state.streams = {}
          if state.streams[req.body.StreamName] is undefined
            state.streams[req.body.StreamName] = {}

          newStreamState =
            id: "arn:aws:kinesis:us-east-1:133713371337:stream/#{req.body.StreamName}"

          for procName, procDefs of (state.processors || {})
            [stateName, otherProc] = req.body.StreamName.split("#{procName}-")
            if otherProc and state.processors?[otherProc] isnt undefined
              newStreamState.to = otherProc
              newStreamState.from = procName
              break

          state.streams[req.body.StreamName] = newStreamState

          console.log "AFTER STREAM CREATE", state.streams
          res.json ok: true
          done null, state

      when 'DescribeStream'
        if streamDefs
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

        if streamDefs
          processorName = @getTargetProcessor state, req.body.StreamName
          data = JSON.parse new Buffer(req.body.Data, 'base64').toString()
          @invokeProcessor processorName, data.data, state, opts, (err, results) ->
            res.json {ok: true}
        else
          res.status 400
          res.header 'x-amzn-errortype', 'ResourceNotFoundException'
          res.json
            message: "Stream not found: #{req.body.StreamName}"

  handleCreateEventSourceMapping: (state, opts, req, res) ->
    allData = ""
    req.on 'data', (data) -> allData += data.toString()
    req.on 'end', ->
      mapping = JSON.parse allData
      console.log "MAPPING DATA", mapping
      res.json extend mapping,
        UUID: uuid.v1()
        LastModified: moment().format()

module.exports = Streams