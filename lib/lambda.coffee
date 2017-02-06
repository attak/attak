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

    runnerPath = require('path').resolve (program.cwd || process.cwd()), './attak_runner.js'

    async.forEachOfSeries topology.processors, (processor, name, next) ->
      if fs.existsSync "#{processor.source}/package.json"
        console.log "PROCESSOR", name, "IS A PACKAGE"
        next()
      else
        console.log "PROCESSOR", name, "IS A FILE"

        prog = extend true, {}, program
        prog.functionName = name
        prog.handler = 'attak_runner.handler'

        fs.writeFileSync runnerPath, """
          var AWS = require('aws-sdk');
          var async = require('async');
          var source = require('#{processor.source}');

          AWS.config.apiVersions = {
            kinesis: '2013-12-02'
          }

          var getNext = function(topology, topic, current) {
            var i, len, next, stream;
            next = [];
            for (i = 0, len = topology.streams.length; i < len; i++) {
              stream = topology.streams[i];
              if (stream.from === current && (stream.topic || topic) === topic) {
                next.push(stream.to);
              }
            }
            return next;
          }

          exports.handler = function(event, context, callback) {
            context.topology = JSON.parse('#{JSON.stringify(topology)}')

            if(event.Records) {
              var payload = new Buffer(event.Records[0].kinesis.data, 'base64').toString('ascii')
              event = JSON.parse(payload);
            }

            context.emit = function(topic, data, opts) {
              var nextProcs = getNext(context.topology, topic, '#{name}')
              async.each(nextProcs, function(nextProc, done) {
                var kinesis = new AWS.Kinesis({
                  region: '#{program.region || "us-east-1"}'
                });

                var params = {
                  Data: new Buffer(JSON.stringify(data)),
                  StreamName: context.topology.name + '-#{name}-' + nextProc,
                  PartitionKey: '#{uuid.v1()}'
                };

                kinesis.putRecord(params, function(err, data) {
                  done()
                });
              }, function() {

              })
            }

            source.handler(event, context, callback);
          }
        """

        lambda.deploy prog, (err, results) ->
          console.log "DEPLOY RESULTS", err, results
          for result in results
            retval[result.FunctionName] = result

          fs.unlink runnerPath, ->
            next()
    , ->
      callback null, retval

module.exports = LambdaUtils