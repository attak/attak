AWS = require 'aws-sdk'
http = require 'http'
uuid = require 'uuid'
ngrok = require 'ngrok'
chalk = require 'chalk'
async = require 'async'
AWSUtils = require './aws'
AttakProc = require 'attak-processor'
TopologyUtils = require './topology'

SimulationUtils =

  defaultReport: (eventName, event) ->
    switch eventName
      when 'emit'
        console.log chalk.blue("emit #{event.processor} : #{event.topic}", JSON.stringify(event.data))
      when 'start'
        console.log chalk.blue("start #{event.processor}")
      when 'end'
        console.log chalk.blue("end #{event.processor} : #{event.end - event.start} ms")
      when 'err'
        console.log chalk.blue("#{eventName} #{event.processor} #{event.err.stack}")
      else
        console.log chalk.blue("#{eventName} #{event.processor} #{JSON.stringify(event)}")

  simulate: (program, topology, processorName, data, report, triggerId, emitCallback, callback) ->
    results = {}
    workingDir = program.cwd || process.cwd()
    
    processor = TopologyUtils.getProcessor program, topology, processorName

    context =
      done: -> callback()
      fail: (err) -> callback err
      success: (results) -> callback null, results
      topology: topology
      kinesisEndpoint: program.kinesisEndpoint

    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'
      endpoint: program.kinesisEndpoint

    nextByTopic = AWSUtils.nextByTopic topology, processorName
    AWSUtils.getIterators kinesis, processorName, nextByTopic, topology, (err, iterators) ->
      startTime = new Date().getTime()

      report 'start',
        processor: processorName
        triggerId: triggerId
        start: startTime

      handler = AttakProc.handler processorName, topology, processor, program
      handler data, context, (err, resultData) ->
        endTime = new Date().getTime()

        if err
          report 'err',
            processor: processorName
            triggerId: triggerId
            start: startTime
            end: endTime
            err: err

          return callback err

        report 'end',
          processor: processorName
          triggerId: triggerId
          start: startTime
          end: endTime

        async.forEachOf nextByTopic, (nextProc, topic, done) ->
          streamName = AWSUtils.getStreamName topology.name, processorName, nextProc
          iterator = iterators[streamName]

          kinesis.getRecords
            ShardIterator: iterator.ShardIterator
          , (err, rawRecords) ->
            iterators[streamName] =
              ShardIterator: rawRecords.NextShardIterator

            records = []
            for record in rawRecords.Records
              dataString = new Buffer(record.Data, 'base64').toString()
              records.push JSON.parse dataString

            for record in records
              emitCallback record.topic, record.data, record.opts

            done err
        , (err) ->
          callback err, resultData

  runSimulations: (program, topology, input, simOpts, callback) ->
    allResults = {}
    SimulationUtils.setupSimulationDeps allResults, program, topology, input, simOpts, ->
      async.eachOf input, (data, processor, next) ->
        SimulationUtils.runSimulation allResults, program, topology, input, simOpts, data, processor, ->
          next()
      , (err) ->
        if topology.api
          console.log "Waiting for incoming requests"
        else
          callback? err, allResults

  setupSimulationDeps: (allResults, program, topology, input, simOpts, callback) ->
    async.waterfall [
      (done) ->
        if topology.api
          SimulationUtils.spoofApi allResults, program, topology, input, simOpts, ->
            done()
        else
          done()
    ], (err, results) ->
      callback()
    
  spoofApi: (allResults, program, topology, input, simOpts, callback) ->
    hostname = '127.0.0.1'
    port = 12369
    
    server = http.createServer (req, res) ->
      event =
        path: req.url
        body: req.body
        headers: req.headers
        httpMethod: req.method
        queryStringParameters: req.query

      SimulationUtils.runSimulation allResults, program, topology, input, simOpts, event, topology.api, ->
        response = allResults[topology.api]?.callback?.results?.body || ''
        try
          respData = JSON.parse response
          res.end respData
        catch e
          res.end response
    
    server.listen port, hostname, ->
      ngrok.connect port, (err, url) ->
        console.log "API running at: http://localhost:#{port}"
        console.log "Externally visible url:", url
        callback()

  runSimulation: (allResults, program, topology, input, simOpts, data, processor, callback) ->
    eventQueue = [{processor: processor, input: data}]
    hasError = false
    procName = undefined
    simData = undefined
    async.whilst () ->
      if hasError then return false

      nextEvent = eventQueue.shift()
      procName = nextEvent?.processor
      simData = nextEvent?.input
      return nextEvent?
    , (done) ->
      numEmitted = 0
      triggerId = uuid.v1()
      report = program.report || simOpts?.report || SimulationUtils.defaultReport

      if allResults[procName] is undefined
        allResults[procName] =
          emits: {}

      SimulationUtils.simulate program, topology, procName, simData, report, triggerId, (topic, emitData, opts) ->
        numEmitted += 1

        report 'emit',
          data: emitData
          topic: topic
          trace: simData.trace || uuid.v1()
          emitId: uuid.v1()
          triggerId: triggerId
          processor: procName

        if allResults[procName].emits[topic] is undefined
          allResults[procName].emits[topic] = []

        allResults[procName].emits[topic].push emitData
        if allResults[procName].emits[topic].length > 1000
          allResults[procName].emits[topic].shift()

        for stream in topology.streams
          if stream.from is procName and (stream.topic || topic) is topic
            eventQueue.push
              processor: stream.to
              input: emitData

      , (err, results) ->
        if err
          hasError = true

        if allResults[procName] is undefined
          allResults[procName] = {}
        allResults[procName].callback = {err, results}

        done err
    , (err) ->
      callback()

module.exports = SimulationUtils