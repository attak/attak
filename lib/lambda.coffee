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
ProgressBar = require 'progress'

DEBUG = true
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

  deployProcessors: (opts, callback) ->
    log "Deploying processors"
    retval = {}
    opts.region = opts.region || 'us-east-1'

    regions = opts.region.split(',')
    environment = opts.environment || 'development'

    bar = new ProgressBar 'uploading :bar', 
      total: Object.keys(opts.processors).length

    runnerPath = require('path').resolve (opts.cwd || process.cwd()), './attak_runner.js'

    fs.writeFileSync runnerPath, """
      var procName = process.env.ATTAK_PROCESSOR_NAME
      var environment = '#{environment}'

      try {
        var attak = require('attak-processor')
        var topology = attak.utils.topology.loadTopology({})
        var impl = attak.utils.topology.getProcessor({}, topology, procName)
        var opts = #{JSON.stringify({region: opts.region, environment: environment})}
        exports.handler = attak.handler(procName, topology, impl, opts)
      
      } catch(err) {
        console.log("ERROR SETTING UP HANDLER", environment, procName, topology, process.env)
        console.log(err.stack)
        exports.handler = function(event, context, callback) {
          if (environment === 'development' || event.attakProcessorVerify) {
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
        functionName = "#{name}-#{opts.environment || 'development'}"

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
            aws_security.accessKeyId = opts.accessKey
            aws_security.secretAccessKey = opts.secretKey
          
          if opts.sessionToken
            aws_security.sessionToken = opts.sessionToken
          
          AWS.config.update aws_security
          
          awsLambda = new AWS.Lambda
            apiVersion: '2015-03-31'
            endpoint: opts.services['AWS:API'].endpoint
          
          awsLambda.getFunction {FunctionName: params.FunctionName}, (err, results) ->
            if err
              log "Creating new function", params.FunctionName
              awsLambda.createFunction params, (err, results) ->
                retval[params.FunctionName] = results
                nextRegion err
            else
              log "Updating existing function", params.FunctionName, params
              retval[params.FunctionName] = results
              LambdaUtils.uploadExisting awsLambda, params, (err, results) ->
                nextRegion err
        
        , (err, results) ->
          bar.tick()
          nextProcessor err
      , (err) ->
        fs.unlink runnerPath, ->
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
    if arch != 'linux.x64'
      console.warn 'Warning!!! You are building on a platform that is not 64-bit Linux (%s). ' + 'If any of your Node dependencies include C-extensions, they may not work as expected in the ' + 'Lambda environment.\n\n', arch

    codeDirectory = lambda._codeDirectory(program)
    lambda._cleanDirectory codeDirectory, (err) ->
      if err
        return callback(err)

      # Move files to tmp folder
      lambda._rsync program, '.', codeDirectory, true, (err) ->
        if err
          return callback(err)
        
        lambda._npmInstall program, codeDirectory, (err) ->
          if err
            return callback(err)

          lambda._postInstallScript program, codeDirectory, (err) ->
            if err
              return callback(err)

            # Add custom environment variables if program.configFile is undefined
            if program.configFile
              lambda._setEnvironmentVars program, codeDirectory

            LambdaUtils.zipDir program, codeDirectory, (err, buffer) ->
              callback err, buffer

module.exports = LambdaUtils