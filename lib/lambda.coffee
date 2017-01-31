fs = require 'fs'
lave = require 'lave'
uuid = require 'node-uuid'
babel = require 'babel-core'
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

    async.forEachOfSeries topology.processors, (processor, name, next) ->
      if fs.existsSync "#{processor.source}/package.json"
        console.log "PROCESSOR", name, "IS A PACKAGE"
        next()
      else
        console.log "PROCESSOR", name, "IS A FILE"

        prog = extend true, {}, program
        prog.functionName = name
        prog.handler = 'attak_runner.handler'

        indexPath = require('path').resolve process.cwd(), './attak_runner.js'

        fs.writeFileSync indexPath, """
          var AWS = require('aws-sdk');
          var source = require('#{processor.source}');
          var credentials = new AWS.SharedIniFileCredentials({
            profile: 'default'
          })

          AWS.config.credentials = credentials
          AWS.config.apiVersions = {
            kinesis: '2013-12-02'
          }

          exports.handler = function(event, context, callback) {
            context.emit = function(data, opts) {
              console.log("EMITTING", data, opts);

              var kinesis = new AWS.Kinesis({
                region: program.region || 'us-east-1'
              });

              var params = {
                Data: new Buffer(JSON.stringify(data)),
                StreamName: stream.StreamName,
                PartitionKey: uuid.v1()
              };

              kinesis.putRecord(params, function(err, data) {});
            }

            source.handler(event, context, callback);
          }
        """

        lambda.deploy prog, (err, results) ->
          console.log "DEPLOY RESULTS", err, results
          for result in results
            retval[result.FunctionName] = result

          next()
    , ->
      callback null, retval

module.exports = LambdaUtils