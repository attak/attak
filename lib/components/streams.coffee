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

  create: (path, defs, opts) ->
    [namespace, name, args...] = path
    if namespace is 'processors'
      streamName = undefined
      for thisName, stream of opts.target.streams
        if stream.to is name or stream.from is name
          streamName = thisName
          defs = stream
    else
      streamName = name

    [
      {
        msg: "Create new stream"
        run: (done) =>
          @createStream streamName, defs, opts, (err, streamData, association) ->
            if err then return done err
            opts.target.streams[streamData.StreamDescription.StreamName].id = streamData.StreamDescription.StreamARN
            done null, opts.target
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
    AWSUtils.createStream opts, opts.target.name, streamName, (err, results) ->
      AWSUtils.describeStream opts, opts.target.name, streamName, (err, streamResults) ->
        if err then return callback err
        targetProcessor = extend true, {}, opts.target.processors[defs.to]
        targetProcessor.name = defs.to

        streamDefs =
          id: streamResults.StreamDescription.StreamARN

        AWSUtils.associateStream opts.target, streamDefs, targetProcessor, opts, (err, associationResults) ->
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

  handleKinesisPut: (state, opts, req, res) =>
    targetId = req.headers['x-amz-target']
    [version, type] = targetId.split '.'

    streamDefs = undefined
    for streamName, stream of (opts.target?.streams || {})
      thisStream = AWSUtils.getStreamName(opts.target.name, stream.from, stream.to)
      if thisStream is req.body.StreamName
        streamDefs = [streamName, stream]
      else
        console.log "NO MATCH", req.body.StreamName, thisStream

    console.log "HANDLE KINESIS PUT", type, streamDefs, req.body

    switch type
      when 'CreateStream'
        console.log "CREATE STREAM", req.body, opts.target, streamDefs

        if streamDefs
          res.header 'x-amzn-errortype', 'ResourceInUseException'
          res.json
            message: "Stream already exists with name #{req.body.StreamName}"
        else
          console.log "STREAMS ARE", req.body.StreamName, Object.keys(opts.target?.streams || {}), opts.target
          opts.target.streams[req.body.StreamName].id = "arn:aws:kinesis:us-east-1:133713371337:stream/#{req.body.StreamName}"

          console.log "AFTER STREAM CREATE", opts.target.streams

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