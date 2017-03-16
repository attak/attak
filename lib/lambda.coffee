fs = require 'fs'
lave = require 'lave'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
lambda = require 'node-lambda'
nodePath = require 'path'

LambdaUtils =

  deployProcessors: (topology, program, callback) ->
    retval = {}

    runnerPath = require('path').resolve (program.cwd || process.cwd()), './attak_runner.js'

    async.forEachOfSeries topology.processors, (processor, name, next) ->
      prog = extend true, {}, program
      prog.functionName = name
      prog.handler = 'attak_runner.handler'

      fs.writeFileSync runnerPath, """
        'use strict'
        var topology = #{JSON.stringify(topology)}
        var procName = '#{name}'
        if (#{processor.source?}) {
          var source = require('#{processor.source}')
        } else {
          try {
            var localTopo = require('.')
            var source = localTopo.processors[procName]
            console.log("SOURCE IS", source.handler || source)
          } catch(err) {
            console.log("CAUGHT ERROR", err, err.stack)
          }
        }
        var attak = require('attak-processor')
        var opts = JSON.parse('#{JSON.stringify({region: program.region})}')
        exports.handler = attak.handler(procName, topology, source, opts)
      """

      lambda.deploy prog, (err, results) ->
        console.log "DEPLOY RESULTS", err, results
        for result in results
          retval[result.FunctionName] = result

        next()
        # fs.unlink runnerPath, ->
        #   next()
    , ->
      callback null, retval

module.exports = LambdaUtils