AWS = require 'aws-sdk'
uuid= require 'uuid'
async = require 'async'
extend = require 'extend'
moment = require 'moment'
AWSUtils = require '../aws'
AttakProc = require 'attak-processor'
TopologyUtils = require '../topology'
BaseComponent = require './base_component'

class Streams extends BaseComponent
  namespace: 'streams'
  platforms: ['AWS']
  dependencies: ['name', 'processors']
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
          if namespace is 'processors'
            [procName, procArgs...] = args
            streams = @getProcessorStreams state, procName
            async.eachSeries streams, ([streamName, streamDefs], nextStream) ->
              @createStream state, streamName, defs[streamName], opts, (err, streamData, association) ->
                if err then return done err

                defs.id = streamData.arn
                state.streams = extend true, state.streams,
                  "#{streamData.name}": streamDefs

                nextStream err
            , (err) ->
              done err, state
          else if namespace is 'streams'
            async.forEachOf defs, (streamDefs, streamName, nextStream) =>
              @createStream state, streamName, defs[streamName], opts, (err, streamData, association) =>
                if err then return done err
                
                defs.id = streamData.arn
                state.streams = extend true, state.streams,
                  "#{streamData.name}": streamDefs

                nextStream err
            , (err) ->
              done err, state
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
    region = opts.region || 'us-east-1'

    iam = new AWS.IAM
      region: region
      endpoint: opts.services['AWS:IAM'].endpoint

    iam.getUser (err, user) ->
      AWSUtils.createStream opts, state.name, streamName, (err, results) ->
        if err then return callback err

        account = user.User.UserId

        streamArn = "arn:aws:kinesis:#{region}:#{account}:stream/#{streamName}"

        targetProcessor = extend true, {}, state.processors[defs.to]
        targetProcessor.name = defs.to

        streamDefs =
          id: streamArn
          arn: streamArn
          name: streamName

        AWSUtils.associateStream state, streamDefs, targetProcessor, opts, (err, associationResults) ->
          state = extend true, state,
            streams:
              "#{streamName}": streamDefs

          callback err, streamDefs, associationResults

  invokeProcessor: (processorName, fullName, data, state, opts, callback) ->
    topology = TopologyUtils.loadTopology opts

    services = {}
    for serviceKey, service of opts.services
      services[serviceKey] =
        endpoint: service.endpoint 
    
    context =
      done: -> callback()
      fail: (err) -> callback err
      success: (results) -> callback null, results
      state: state
      topology: topology
      services: services
      functionName: fullName

    {impl} = TopologyUtils.getProcessor opts, topology, processorName
    handler = AttakProc.handler processorName, topology, impl, opts
    handler data, context, (err, results) ->
      callback err, results

  getTargetProcessor: (state, targetStream) ->
    for streamName, stream of (state.streams || {})
      streamName = AWSUtils.getStreamName state.name, stream.from, stream.to
      if streamName is targetStream
        return stream.to

  handleKinesisPut: (state, opts, req, res) =>
    targetId = req.headers['x-amz-target']
    [version, type] = targetId.split '.'

    if state.name is undefined and state.processors
      for procName, procDefs of state.processors
        [thisStateName, otherProc] = req.body.StreamName.split("-#{procName}-")
        if otherProc and state.processors?[otherProc] isnt undefined
          stateName = thisStateName
          break
    else
      stateName = state.name

    streamDefs = undefined
    for streamName, stream of (state.streams || {})
      thisStream = AWSUtils.getStreamName(stateName, stream.from, stream.to)
      if thisStream is req.body.StreamName
        streamDefs = [streamName, stream]

    switch type
      when 'CreateStream'
        if streamDefs
          res.header 'x-amzn-errortype', 'ResourceInUseException'
          res.json
            message: "Stream already exists with name #{req.body.StreamName}"
        else
          #   Arn: "arn:aws:kinesis:us-east-1:133713371337:stream/#{req.body.StreamName}"
          res.json ok: true

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
        if streamDefs
          processorName = @getTargetProcessor state, req.body.StreamName
          data = JSON.parse new Buffer(req.body.Data, 'base64').toString()
          functionName = AWSUtils.getFunctionName state.name, processorName, opts.environment || 'development'
          @invokeProcessor processorName, functionName, data.data, state, opts, (err, results) ->
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
      res.json extend mapping,
        UUID: uuid.v1()
        LastModified: moment().format()

module.exports = Streams