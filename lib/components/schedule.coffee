AWS = require 'aws-sdk'
uuid = require 'uuid'
async = require 'async'
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
        run: (done) ->
          console.log "CREATING SCHEDULE", opts.target
          AWSUtils.setupSchedule opts.target, opts, (err, results) ->
            console.log "SCHEDULE SETUP RESULTS", err, results
            done err
      }
    ]

  delete: (path, oldDefs, callback) ->
    [
      {
        msg: 'Remove name'
        run: (done) ->
          console.log "REMOVING SCHEDULE", path
          done()
      }
    ]

  handlePost: (state, opts, req, res) ->
    target = req.headers['x-amz-target'].split('AWSEvents.')[1]
    console.log "HANDLE POST", target, req.body, req.headers, opts.target
    switch target
      when 'PutRule'

        eventName = req.body.Name.split("#{opts.target.name}-")[1]
        arn = "arn:aws:events:us-east-1:133713371337:rule/#{eventName}"
        console.log "GOT EVENT NAME", eventName, arn
        opts.target.schedule[eventName].id = arn

        res.json
          RuleArn: arn
      
      when 'PutTargets'
        res.json
          FailedEntries: [],
          FailedEntryCount: 0
      else
        console.log "UNKNOWN SCHEDULE TARGET", target


module.exports = Schedule