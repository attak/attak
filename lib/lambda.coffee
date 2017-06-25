fs = require 'fs'
AWS = require 'aws-sdk'
uuid = require 'uuid'
klaw = require 'klaw'
JSZip = require 'jszip'
async = require 'async'
extend = require 'extend'
lambda = require 'node-lambda'
NodeZip = require 'node-zip'
nodePath = require 'path'
AWSUtils = require './aws'

DEBUG = false
log = -> if DEBUG then console.log arguments...

LambdaUtils =

  getProcessorInfo: (topology, opts, callback) ->
    awsLambda = new AWS.Lambda
      region: opts.region || 'us-east-1'

    lambdas = {}
    async.forEachOf topology.processors, (processor, name, next) ->
      functionName = "#{name}-#{opts.environment || 'development'}"
      params =
        FunctionName: functionName

      awsLambda.getFunction params, (err, results) ->
        lambdas[functionName] = results
        next()
    , (err) ->
      callback err, lambdas

  deployProcessors: (state, opts, callback) ->
    log "Deploying processors"
    retval = {}
    opts.region = opts.region || 'us-east-1'

    regions = opts.region.split(',')
    environment = opts.environment || 'development'

    runnerPath = require('path').resolve (opts.cwd || process.cwd()), './attak_runner.js'
    optsStr = JSON.stringify({region: opts.region, environment: environment})

    fs.writeFileSync runnerPath, """
      var procName = process.env.ATTAK_PROCESSOR_NAME
      var environment = '#{environment}'

      try {
        var attak = require('attak-processor')
        var topology = attak.utils.topology.loadTopology({})
        var loaded = attak.utils.topology.getProcessor({}, topology, procName)
        var opts = #{optsStr}
        exports.handler = attak.handler(procName, topology, loaded.impl, opts)
      
      } catch(err) {
        console.log("ERROR SETTING UP HANDLER", environment, procName, topology, process.env)
        console.log(err.stack)
        exports.handler = function(event, context, callback) {
          if (event.attakProcessorVerify) {
            callback(null, err)
          } else {
            callback(err)
          }
        }
      }
    """

    log "Build and archive"
    LambdaUtils.buildAndArchive opts, (err, buffer) ->
      if err
        return callback err

      log "Deploying #{Object.keys(opts.processors).length} processors"

      async.forEachOf opts.processors, (processor, name, nextProcessor) ->
        functionName = AWSUtils.getFunctionName state.name, name, environment

        params = 
          FunctionName: functionName
          Code: ZipFile: buffer
          Handler: 'attak_runner.handler'
          Role: opts.role || process.env.AWS_ROLE_ARN || process.env.AWS_ROLE || 'missing'
          Runtime: opts.runtime || process.env.AWS_RUNTIME || 'nodejs4.3'
          Description: opts.description
          MemorySize: opts.memorySize || process.env.AWS_MEMORY_SIZE || 128
          Timeout: opts.timeout || process.env.AWS_TIMEOUT || 60
          Publish: opts.publish || process.env.AWS_PUBLISH || false
          VpcConfig: {}
          Environment:
            Variables:
              ATTAK_TOPOLOGY_NAME: opts.name
              ATTAK_PROCESSOR_NAME: name

        if opts.vpcSubnets and opts.vpcSecurityGroups
          params.VpcConfig =
            SubnetIds: opts.vpcSubnets.split ','
            SecurityGroupIds: opts.vpcSecurityGroups.split ','

        async.map regions, (region, nextRegion) ->
          aws_security = region: region
          
          if opts.profile
            AWS.config.credentials = new AWS.SharedIniFileCredentials
              profile: opts.profile
          else
            aws_security.accessKeyId = opts.accessKey || process.env.AWS_ACCESS_KEY_ID
            aws_security.secretAccessKey = opts.secretKey || process.env.AWS_SECRET_ACCESS_KEY
          
          if opts.sessionToken
            aws_security.sessionToken = opts.sessionToken
          
          AWS.config.update aws_security
          
          awsLambda = new AWS.Lambda
            apiVersion: '2015-03-31'
            endpoint: opts.services?['AWS:API'].endpoint
          
          awsLambda.getFunction {FunctionName: params.FunctionName}, (err, results) ->
            if err
              log "Creating new function", params.FunctionName
              awsLambda.createFunction params, (err, results) ->
                retval[params.FunctionName] = [err, results]
                nextRegion err
            else
              log "Updating existing function", params.FunctionName
              LambdaUtils.uploadExisting awsLambda, params, (err, results) ->
                retval[params.FunctionName] = [err, results]
                nextRegion err
        
        , (err, results) ->
          nextProcessor err
      , (err) ->
        if fs.existsSync runnerPath
          fs.unlink runnerPath, ->
            callback err, retval
        else
          callback err, retval

  uploadExisting: (awsLambda, params, callback) ->
    awsLambda.updateFunctionCode
      FunctionName: params.FunctionName
      ZipFile: params.Code.ZipFile
      Publish: params.Publish
    , (err, data) ->
      log "UPDATE CODE RESULTS", err, data
      if err
        return callback(err, data)
      
      awsLambda.updateFunctionConfiguration
        FunctionName: params.FunctionName
        Description: params.Description
        Handler: params.Handler
        MemorySize: params.MemorySize
        Role: params.Role
        Timeout: params.Timeout
        VpcConfig: params.VpcConfig
        Environment: params.Environment
      , (err, data) ->
        log "UPDATE CONFIG RESULTS", err, data
        callback err, data

  createSampleFile: (file, boilerplateName) ->
    exampleFile = process.cwd() + '/' + file
    boilerplateFile = __dirname + '/' + (boilerplateName or file) + '.example'
    if !fs.existsSync(exampleFile)
      fs.writeFileSync exampleFile, fs.readFileSync(boilerplateFile)
      console.log exampleFile + ' file successfully created'

  zipDir: (program, codeDirectory, callback) ->
    zip = new NodeZip
    options =
      type: 'nodebuffer'
      compression: 'DEFLATE'

    klaw(codeDirectory)
      .on 'data', (file) ->
        if !file.stats.isDirectory()
          content = fs.readFileSync(file.path)
          filePath = file.path.replace(codeDirectory + '/', '')
          zip.file filePath, content

      .on 'end', ->
        data = zip.generate options
        callback null, data

  buildAndArchive: (program, callback) ->
    if program.simulation
      return callback()

    # Warn if not building on 64-bit linux
    arch = process.platform + '.' + process.arch

    cwd = program.cwd || process.cwd()

    codeDirectory = lambda._codeDirectory(program)
    log "CLEANING DIRECTORY"
    lambda._cleanDirectory codeDirectory, (err) ->
      if err
        return callback(err)

      # Move files to tmp folder
      log "MOVING TO TMP DIR"
      lambda._rsync program, cwd, codeDirectory, true, (err) ->
        if err
          return callback(err)
        
        log "NPM INSTALL PRODUCTION"
        lambda._npmInstall program, codeDirectory, (err) ->
          if err
            return callback(err)

          log "POST INSTALL"
          lambda._postInstallScript program, codeDirectory, (err) ->
            if err
              return callback(err)

            # Add custom environment variables if program.configFile is undefined
            if program.configFile
              lambda._setEnvironmentVars program, codeDirectory

            log "ZIP"
            LambdaUtils.zipDir program, codeDirectory, (err, buffer) ->
              log "DONE"
              callback err, buffer

module.exports = LambdaUtils