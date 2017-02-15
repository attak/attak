fs = require 'fs'
lave = require 'lave'
uuid = require 'uuid'
async = require 'async'
recast = require 'recast'
extend = require 'extend'
mkdirp = require 'mkdirp'
lambda = require 'node-lambda'
nodePath = require 'path'
{generate} = require 'escodegen'
regenerator = require 'regenerator'

LambdaUtils =

  deployProcessors: (topology, program, callback) ->
    retval = {}

    runnerPath = require('path').resolve (program.cwd || process.cwd()), './attak_runner.js'

    async.forEachOfSeries topology.processors, (processor, name, next) ->
      prog = extend true, {}, program
      prog.functionName = name
      prog.handler = 'attak_runner.handler'

      fs.writeFileSync runnerPath, """
        var attak = require('attak-processor');
        var opts = JSON.parse('#{JSON.stringify({region: program.region})}');
        var topology = JSON.parse('#{JSON.stringify(topology)}');
        var source = require('#{processor.source}');
        exports.handler = attak.handler('#{name}', topology, source, opts);
      """

      lambda.deploy prog, (err, results) ->
        for result in results
          retval[result.FunctionName] = result

        fs.unlink runnerPath, ->
          next()
    , ->
      callback null, retval

module.exports = LambdaUtils