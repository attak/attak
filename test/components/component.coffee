fs = require 'fs'
tape = require 'tape'
tapes = require 'tapes'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
BaseComponent = require '../../lib/components/base_component'  

test = tapes tape

test 'components', (suite) ->

  suite.test 'base component', (suite) ->
    
    suite.test 'simulation services', (suite) ->

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

      suite.beforeEach (suite) ->
        @component = new ParentComponent
        suite.end()

      suite.test 'should get config data from inside an array', (suite) ->
        services = @component.getSimulationServices()
        suite.equal services?['other:parent:service']?.some, 'config'
        suite.end()

      suite.test 'should fetch a list of simulation services', (suite) ->
        services = @component.getSimulationServices()
        
        suite.notEqual services, undefined, 'failed to find any services'
        suite.notEqual services.length, 0
        suite.notEqual services['parent:service'], undefined, 'failed to find top level component services'
        suite.notEqual services['other:parent:service'], undefined, 'failed to find top level component services'
        suite.notEqual services['child:service'], undefined, 'failed to find child services'

        suite.end()
      suite.end()
    suite.end()


    suite.test 'required impl errors', (suite) ->

      suite.test 'gets state', (suite) ->
        suite.doesNotThrow =>
          @component.getState (err, results) ->
            suite.notEqual err, undefined, 'failed to throw an error for missing implementation'
        , undefined, 'failed to throw an error for missing implementation'
        
        suite.end()

      suite.test 'resolveDiff', (suite) ->
        suite.doesNotThrow =>
          @component.getState (err, results) ->
            suite.notEqual err, undefined, 'failed to throw an error for missing implementation'
        , undefined, 'failed to throw an error for missing implementation'

        suite.end()
      suite.end()
    
    suite.test 'setState', (suite) ->

      class SimpleComponent extends BaseComponent
        getState: (callback) ->
          if @state is undefined
            @state = {}
          callback null, @state

        resolveState: (currentState, newState, differences, opts, callback) ->
          @state = newState
          callback()

      suite.beforeEach (suite) ->
        @component = new SimpleComponent
        suite.end()

      suite.test 'should set state successfully', (suite) ->
        @component.setState {}, {working: true}, {}, (err, results) =>
          @component.getState (err, state) ->
            differences = Differ.diff state, {working: true}
            suite.equal differences?.length > 0, false, 'failed to set state'

            suite.end()
      suite.end()

  suite.test 'generic tests', (suite) ->
    files = fs.readdirSync __dirname

    for file in files
      if file is 'component.coffee' then continue
      fullPath = nodePath.resolve(__dirname, "../../lib/components/#{file}")
      Component = require fullPath
      component = new Component

      componentName = nodePath.basename file, '.coffee'

      suite.test componentName, (suite) =>

        suite.test 'should provide a list of supported platforms', (suite) ->
          suite.notEqual component.platforms, undefined

          suite.end()
        suite.end()
    suite.end()
  suite.end()