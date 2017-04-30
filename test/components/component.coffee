require 'coffee-errors'

fs = require 'fs'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
BaseComponent = require '../../lib/components/base_component'  

describe 'components', ->
  describe 'base component', ->
    before (done) ->
      @component = new BaseComponent
      done()

    describe 'simulation services', ->

      class ChildComponent extends BaseComponent
        simulation:
          services: [
            'child:service'
          ]

      class ParentComponent extends BaseComponent
        simulation:
          services: [
            'parent:service'
            {
              'other:parent:service': {some: 'config'}
            }
          ]

        constructor: (@options) ->
          super @options
          @children =
            testChild: new ChildComponent

      before (done) ->
        @component = new ParentComponent
        done()

      it 'should get config data from inside an array', (done) ->
        services = @component.getSimulationServices()
        if services?['other:parent:service']?.some is 'config'
          done()
        else
          done 'failed to get service config from inside services array'

      it 'should fetch a list of simulation services', (done) ->
        services = @component.getSimulationServices()
        
        if services is undefined
          return done 'returned undefined services'

        if services.length is 0
          return done 'failed to find any services'

        if services['parent:service'] is undefined or services['other:parent:service'] is undefined
          return done 'failed to find top level component services'

        if services['child:service'] is undefined
          return done 'failed to find child services'

        done()

    describe 'required impl errors', ->

      it 'getState', (done) ->
        try
          @component.getState (err, results) ->
            if err then return done()
            done 'failed to throw an error for missing implementation'
        catch e
          done()

      it 'resolveDiff', (done) ->
        try
          @component.getState (err, results) ->
            if err then return done()
            done 'failed to throw an error for missing implementation'
        catch e
          done()
    
    describe 'setState', ->

      class SimpleComponent extends BaseComponent
        getState: (callback) ->
          if @state is undefined
            @state = {}
          callback null, @state

        resolveState: (currentState, newState, differences, callback) ->
          @state = newState
          callback()

      before (done) ->
        @component = new SimpleComponent
        done()

      it 'should set state successfully', (done) ->
        @component.setState {working: true}, (err, results) =>
          @component.getState (err, state) ->
            differences = Differ.diff state, {working: true}
            if differences?.length > 0
              done 'failed to set state'
            else
              done()

  describe 'generic tests', ->
    files = fs.readdirSync __dirname

    for file in files
      if file is 'component.coffee' then continue
      fullPath = nodePath.resolve(__dirname, "../../lib/components/#{file}")
      Component = require fullPath
      component = new Component

      componentName = nodePath.basename file, '.coffee'

      describe componentName, =>

        it 'should provide a list of supported platforms', (done) ->
          if component.platforms is undefined
            done 'failed to provide platform list'
          else
            done()