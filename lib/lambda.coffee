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
        var attak = require('attak-processor')
        
        var procName = '#{name}'
        var topology = attak.utils.topology.loadTopology({})
        var impl = attak.getProcessor({}, topology, procName)
        var opts = #{JSON.stringify({region: program.region})}

        exports.handler = attak.handler(procName, topology, impl, opts)
      """

      lambda.deploy prog, (err, results) ->
        for result in results
          retval[result.FunctionName] = result

        fs.unlink runnerPath, ->
          next()
    , ->
      callback null, retval

module.exports = LambdaUtils