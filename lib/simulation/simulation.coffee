fs = require 'fs'
AWS = require 'aws-sdk'
http = require 'http'
uuid = require 'uuid'
ngrok = require 'ngrok'
chalk = require 'chalk'
async = require 'async'
ATTAK = require '../attak'
parser = require 'cron-parser'
nodePath = require 'path'
dynalite = require 'dynalite'
AWSUtils = require '../aws'
AttakProc = require 'attak-processor'
kinesalite = require 'kinesalite'
staticHost = require 'node-static'
TopologyUtils = require '../topology'
ServiceManager = require './service_manager'

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
      endpoints: program.endpoints

    kinesis = new AWS.Kinesis
      region: program.region || 'us-east-1'
      endpoint: program.endpoints.kinesis

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
            ShardIterator: iterator?.ShardIterator
          , (err, rawRecords) ->
            iterators[streamName] =
              ShardIterator: rawRecords?.NextShardIterator

            records = []
            for record in (rawRecords?.Records || [])
              dataString = new Buffer(record.Data, 'base64').toString()
              records.push JSON.parse dataString

            for record in records
              emitCallback record.topic, record.data, record.opts

            done err
        , (err) ->
          callback err, resultData

  setupAndRun: (opts, callback) ->
    topology = TopologyUtils.loadTopology opts

    opts.startTime = new Date
    opts.environment = opts.environment || 'development'

    app = new ATTAK
      topology: topology
      simulation: true
      environment: opts.environment

    app.setup ->
      services = app.getSimulationServices()
      console.log "SERVICES", services

      manager = new ServiceManager
      manager.setup services, (err, services) ->
        console.log "ALL SETUP", err, services
        app.setState topology, (err, results) ->
          console.log "SET STATE RESULTS", err, results

  oldThing: ->
    if opts.input
      input = opts.input
    else
      inputPath = nodePath.resolve (opts.cwd || process.cwd()), opts.inputFile
      if fs.existsSync inputPath
        input = require inputPath
      else
        input = undefined

    if opts.id
      CommUtils.connect opts, (socket, wrtc) ->
        wrtc.emit 'topology',
          topology: topology

        emitter = wrtc.emit
        wrtc.reconnect = (wrtc) ->
          emitter = wrtc.emit

        simOpts =
          report: () ->
            emitter? arguments...

        SimulationUtils.runSimulations opts, topology, input, simOpts, callback

    else
      SimulationUtils.runSimulations opts, topology, input, {}, callback

  runSimulations: (program, topology, input, simOpts, callback) ->
    allResults = {}
    SimulationUtils.setupSimulationDeps allResults, program, topology, simOpts, (err, endpoints) ->
      AWSUtils.deploySimulationStreams program, topology, (streamNames) ->
        async.eachOf input, (data, processor, next) ->
          SimulationUtils.runSimulation allResults, program, topology, simOpts, data, processor, ->
            next()
        , (err) ->
          if topology.api
            console.log "Waiting for incoming requests"
          else if topology.schedule
            console.log "Waiting for scheduled events"
          else if topology.static
            console.log "Waiting to serve static content"
          else
            callback? err, allResults

  setupSimulationDeps: (allResults, program, topology, simOpts, callback) ->
    program.endpoints = {}

    async.parallel [
      (done) ->
        if SimulationUtils.kinesaliteServer
          return done() 

        SimulationUtils.kinesaliteServer = kinesalite
          path: nodePath.resolve __dirname, '../../kinesisdb'
          createStreamMs: 0

        SimulationUtils.kinesaliteServer.listen 6668, (err) ->
          program.endpoints.kinesis = 'http://localhost:6668'
          done()

      (done) ->
        if SimulationUtils.dynaliteServer
          return done() 

        SimulationUtils.dynaliteServer = dynalite
          path: nodePath.resolve __dirname, '../../dynamodb'
          createStreamMs: 0

        SimulationUtils.dynaliteServer.listen 6698, (err) ->
          program.endpoints.dynamodb = 'http://localhost:6698'
          done()

      (done) ->
        if SimulationUtils.hasSpoofAWS
          return done()
        SimulationUtils.spoofAWS allResults, program, topology, simOpts, (err, url) ->
          SimulationUtils.hasSpoofAWS = true
          
          iot = new AWS.Iot
            region: program.region || 'us-east-1'

          iot.describeEndpoint {}, (err, results) ->
            program.endpoints.aws = url
            program.endpoints.iot = results?.endpointAddress
            done err

      (done) ->
        if topology.api
          SimulationUtils.spoofApi allResults, program, topology, simOpts, (err, url) ->
            program.endpoints.api = url
            done err
        else
          done()

      (done) ->
        if topology.static
          SimulationUtils.spoofStaticHosting allResults, program, topology, simOpts, (err, url) ->
            program.endpoints.static = url
            done err
        else
          done()

      (done) ->
        if topology.schedule
          SimulationUtils.spoofScheduler allResults, program, topology, simOpts, (err, results) ->
            done err
        else
          done()

    ], (err) ->
      if topology.provision
        config =
          aws:
            endpoints: program.endpoints

        topology.provision topology, config, (err) ->
          callback err, program.endpoints
      else
        callback err, program.endpoints

  spoofScheduler: (allResults, program, topology, simOpts, callback) ->
    start = new Date().getTime()

    triggerEvent = (procName, defs) ->
      console.log "EVENT TIME", new Date().getTime() - start
      SimulationUtils.runSimulation allResults, program, topology, simOpts, defs, procName, ->
        null

    async.each topology.schedule, (defs, next) ->
      if defs.type is 'cron'
        interval = parser.parseExpression defs.value

        runNext = ->
          nextTime = interval.next().getTime() - new Date().getTime()
          console.log "NEXT TIME IS", nextTime
          setTimeout ->
            triggerEvent defs.processor, defs
            runNext()
          , nextTime

        runNext()

      else
        [strNum, unit] = defs.value.split ' '
        num = Number strNum
        multiplier = switch unit
          when 'minute', 'minutes'
            1000 * 60
          when 'hour', 'hours'
            1000 * 60 * 60
          when 'day', 'days'
            1000 * 60 * 60 * 24

        setInterval ->
          triggerEvent defs.processor, defs
        , num * multiplier
        
      next()
    , ->
      callback()

  spoofAWS: (allResults, program, topology, simOpts, callback) ->
    hostname = '127.0.0.1'
    port = 12368
    
    server = http.createServer (req, res) ->
      body = ''
      req.on 'data', (data) ->
        body += data
      
      req.on 'end', () ->
        try
          body = JSON.parse body
        catch e

        headers =
          'Access-Control-Max-Age': '86400'
          'Access-Control-Allow-Origin': '*'
          'Access-Control-Allow-Methods': 'POST, GET, PUT, DELETE, OPTIONS'
          'Access-Control-Allow-Headers': 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Accept, X-Amz-Content-Sha256, X-Amz-User-Agent, x-amz-security-token, X-Amz-Date, X-Amz-Invocation-Type, Authorization'
          'Access-Control-Expose-Headers': 'x-amzn-RequestId,x-amzn-ErrorType,x-amzn-ErrorMessage,Date,x-amz-log-result,x-amz-function-error'
          'Access-Control-Allow-Credentials': false

        res.writeHead 200, headers

        if req.method is 'OPTIONS' or req.url.indexOf('/functions/') is -1
          return res.end()

        environment = program.environment || 'development'

        splitPath = req.url.split '/'
        fullName = splitPath[3]
        functionName = fullName.split("-#{environment}")[0]

        event =
          path: req.url
          body: body
          headers: req.headers
          httpMethod: req.method
          queryStringParameters: req.query

        SimulationUtils.runSimulation allResults, program, topology, simOpts, event, functionName, ->
          if allResults[functionName]?.callback.err
            res.writeHead 500
            return res.end allResults[functionName]?.callback.err.stack

          response = allResults[functionName]?.callback?.results?.body || ''
          if not response
            return res.end()

          try
            respData = JSON.parse response
            if respData.status or respData.httpStatus or respData.headers
              res.writeHead (respData.status || respData.httpStatus || 200), respData.headers
            res.end respData
          catch e
            res.end response
    
    server.listen port, hostname, ->
      callback null, "http://localhost:#{port}"

  spoofStaticHosting: (allResults, program, topology, simOpts, callback) ->
    workingDir = program.cwd || process.cwd()
    hostname = '127.0.0.1'
    port = 12342

    if topology.static.constructor is String
      staticDir = nodePath.resolve workingDir, topology.static
    else
      staticDir = nodePath.resolve workingDir, topology.static.dir

    file = new staticHost.Server staticDir

    server = http.createServer (req, res) ->
      req.addListener 'end', ->
        file.serve req, res
      .resume()
    
    server.listen port, hostname, ->
      unless simOpts.silent is true
        console.log "Static files hosted at: http://localhost:#{port}/[file path]"
        # console.log "Externally visible url: #{url}/[file [path]"
      callback null, "http://localhost:#{port}"

  spoofApi: (allResults, program, topology, simOpts, callback) ->
    hostname = '127.0.0.1'
    port = 12369
    
    server = http.createServer (req, res) ->
      if program.endpoints is undefined
        return res.end()

      event =
        path: req.url
        body: req.body
        headers: req.headers
        httpMethod: req.method
        queryStringParameters: req.query

      SimulationUtils.runSimulation allResults, program, topology, simOpts, event, topology.api, ->
        if allResults[topology.api]?.callback.err
          res.writeHead 500
          return res.end allResults[topology.api]?.callback.err.stack

        response = allResults[topology.api]?.callback?.results?.body || ''
        if not response
          return res.end()

        try
          respData = JSON.parse response
          if respData.status or respData.httpStatus or respData.headers
            res.writeHead (respData.status || respData.httpStatus || 200), respData.headers
          res.end respData
        catch e
          res.end response
    
    server.listen port, hostname, ->
      if simOpts.publicUrl is true
        ngrok.connect port, (err, url) ->
          unless simOpts.silent
            console.log "API running at: http://localhost:#{port}"
            console.log "Externally visible url:", url
          callback null, "http://localhost:#{port}"
      else
        unless simOpts.silent
          console.log "API running at: http://localhost:#{port}"
        callback null, "http://localhost:#{port}"

  runSimulation: (allResults, program, topology, simOpts, data, processor, callback) ->
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