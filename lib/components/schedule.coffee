AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
extend = require 'extend'
AWSUtils = require '../aws'
BaseComponent = require './base_component'

class Schedule extends BaseComponent
  namespace: 'schedule'
  required: true

  simulation:
    services: ->
      'AWS:CloudWatchEvents':
        handlers:
          "POST /": @handlePost
  
  structure:
    ':scheduleName':
      id: 'string'
      type: 'string'
      value: 'string'
      handler: '/processors/:processorName/*'

  create: (path, newDefs, opts) ->
    # Creating a new name is a noop
    [
      {
        msg: 'create new schedule item'
        run: (state, done) ->
          async.forEachOf newDefs, (defs, scheduleName, next) ->

            state = extend true, state,
              schedule:
                "#{scheduleName}": defs

            AWSUtils.setupSchedule state, opts, (err, results) ->
              state = extend true, state,
                schedule:
                  "#{scheduleName}":
                    id: results

              next err          
          , (err) ->
            done err, state
      }
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'Remove name'
        run: (state, done) ->
          console.log "REMOVING SCHEDULE", path
          done()
      }
    ]

  handlePost: (state, opts, req, res) ->
    target = req.headers['x-amz-target'].split('AWSEvents.')[1]

    switch target
      when 'PutRule'

        eventName = req.body.Name.split("#{state.name}-")[1]
        arn = "arn:aws:events:us-east-1:133713371337:rule/#{eventName}"

        res.json
          RuleArn: arn
      
      when 'PutTargets'
        res.json
          FailedEntries: [],
          FailedEntryCount: 0
      else
        console.log "UNKNOWN SCHEDULE TARGET", target


module.exports = Schedule