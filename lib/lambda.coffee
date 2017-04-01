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

LambdaUtils =

  # deployProcessors: (topology, program, callback) ->
  #   retval = {}

  #   runnerPath = require('path').resolve (program.cwd || process.cwd()), './attak_runner.js'

  #   # npm install and zip directory
  #   # for each processor
  #   #   add runner to zip

  #   async.forEachOfSeries topology.processors, (processor, name, next) ->
  #     prog = extend true, {}, program
  #     prog.functionName = name
  #     prog.handler = 'attak_runner.handler'

  #     fs.writeFileSync runnerPath, """
  #       'use strict'
  #       try {
  #         var attak = require('attak-processor')
        
  #         var procName = '#{name}'
  #         var topology = attak.utils.topology.loadTopology({})
  #         var impl = attak.utils.topology.getProcessor({}, topology, procName)
  #         var opts = #{JSON.stringify({region: program.region})}

  #         exports.handler = attak.handler(procName, topology, impl, opts)
  #       } catch(err) {
  #         console.log("ERROR SETTING UP HANDLER", err)
  #         exports.handler = function(event, context, callback) {
  #           callback(err)
  #         }
  #       }
  #     """

  #     lambda.deploy prog, (err, results) ->
  #       for result in results
  #         retval[result.FunctionName] = result

  #       fs.unlink runnerPath, ->
  #         next()
  #   , (err) ->
  #     callback err, retval

  deployProcessors: (topology, program, callback) ->
    retval = {}
    regions = program.region.split(',')

    runnerPath = require('path').resolve (program.cwd || process.cwd()), './attak_runner.js'

    fs.writeFileSync runnerPath, """
      'use strict'
      try {
        var attak = require('attak-processor')
      
        var procName = process.env.ATTAK_PROCESSOR_NAME
        var topology = attak.utils.topology.loadTopology({})
        var impl = attak.utils.topology.getProcessor({}, topology, procName)
        var opts = #{JSON.stringify({region: program.region})}

        exports.handler = attak.handler(procName, topology, impl, opts)
      } catch(err) {
        console.log("ERROR SETTING UP HANDLER", err)
        exports.handler = function(event, context, callback) {
          callback(err)
        }
      }
    """

    LambdaUtils.buildAndArchive program, (err, buffer) ->
      if err
        return callback err

      async.forEachOf topology.processors, (processor, name, nextProcessor) ->
        console.log "DEPLOYING", name
        # zip.file './attak_runner.js', new Buffer """
        #   'use strict'
        #   try {
        #     var attak = require('attak-processor')
          
        #     var procName = process.env.ATTAK_PROCESSOR_NAME
        #     var topology = attak.utils.topology.loadTopology({})
        #     var impl = attak.utils.topology.getProcessor({}, topology, procName)
        #     var opts = #{JSON.stringify({region: program.region})}

        #     exports.handler = attak.handler(procName, topology, impl, opts)
        #   } catch(err) {
        #     console.log("ERROR SETTING UP HANDLER", err)
        #     exports.handler = function(event, context, callback) {
        #       callback(err)
        #     }
        #   }
        # """
        
        # genOpts =
        #   type: 'nodebuffer'
        #   compression: 'DEFLATE'

        functionName = "#{name}-#{program.environment || 'development'}"

        params = 
          FunctionName: functionName
          Code: ZipFile: buffer
          Handler: program.handler
          Role: program.role
          Runtime: program.runtime
          Description: program.description
          MemorySize: program.memorySize
          Timeout: program.timeout
          Publish: program.publish
          VpcConfig: {}
          Environment:
            Variables:
              ATTAK_PROCESSOR_NAME: functionName

        if program.vpcSubnets and program.vpcSecurityGroups
          params.VpcConfig =
            SubnetIds: program.vpcSubnets.split ','
            SecurityGroupIds: program.vpcSecurityGroups.split ','

        async.map regions, (region, nextRegion) ->
          aws_security = region: region
          
          if program.profile
            AWS.config.credentials = new AWS.SharedIniFileCredentials
              profile: program.profile
          else
            aws_security.accessKeyId = program.accessKey
            aws_security.secretAccessKey = program.secretKey
          
          if program.sessionToken
            aws_security.sessionToken = program.sessionToken
          
          AWS.config.update aws_security
          
          awsLambda = new AWS.Lambda
            apiVersion: '2015-03-31'
          
          awsLambda.getFunction {FunctionName: params.FunctionName}, (err, results) ->
            if err
              console.log "CREATE FUNCTION", functionName
              awsLambda.createFunction params, (err, results) ->
                retval[params.FunctionName] = results
                nextRegion err
            else
              retval[params.FunctionName] = results
              console.log "UPDATE FUNCTION", functionName
              LambdaUtils.uploadExisting awsLambda, params, (err, results) ->
                nextRegion err
        
        , (err, results) ->
          console.log "FINISHED DEPLOYING", name
          nextProcessor err
      , (err) ->
        console.log "FINISHED DEPLOYING", err, retval
        callback err, retval

  uploadExisting: (awsLambda, params, callback) ->
    awsLambda.updateFunctionCode
      FunctionName: params.FunctionName
      ZipFile: params.Code.ZipFile
      Publish: params.Publish
    , (err, data) ->
      console.log "UPDATED FUNCTION", params.FunctionName
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
      , (err, data) ->
        console.log "UPDATED FN CONFIG", params.FunctionName, err, data
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
    LambdaUtils.createSampleFile '.env', '.env'

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

            # Add custom environment variables if program.configFile is defined
            if program.configFile
              lambda._setEnvironmentVars program, codeDirectory

            LambdaUtils.zipDir program, codeDirectory, (err, buffer) ->
              callback err, buffer

module.exports = LambdaUtils