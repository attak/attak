fs = require 'fs'
test = require 'tape'
tapes = require 'tapes'
attak = require '../../'
Differ = require 'deep-diff'
nodePath = require 'path'
BaseComponent = require '../../lib/components/base_component'  

test 'components', (test) ->

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

  component = new ParentComponent
  services = component.getSimulationServices()
  test.notEqual services, undefined, 'failed to find any services'
  test.notEqual services['parent:service'], undefined, 'should find top level component services'
  test.notEqual services['child:service'], undefined, 'should find child services'
  
  test.notEqual services['other:parent:service'], undefined, 'should find top level component services'
  test.equal services?['other:parent:service']?.some, 'config', 'should resolve parent services'

  test.doesNotThrow =>
    component.getState (err, results) ->
      test.notEqual err, undefined, 'should throw an error for missing implementation'
  , undefined, 'should throw an error for missing implementation'

  class SimpleComponent extends BaseComponent
    getState: (callback) ->
      if @state is undefined
        @state = {}
      callback null, @state

    resolveState: (currentState, newState, differences, opts, callback) ->
      @state = newState
      callback()

  component = new SimpleComponent
  component.setState {}, {working: true}, {}, (err, results) =>
    component.getState (err, state) ->
      differences = Differ.diff state, {working: true}
      test.equal differences?.length > 0, false, 'should be able to set state'
      test.equal err, null, 'should be able to set state without error'

    files = fs.readdirSync nodePath.resolve(__dirname, "../../lib/components")

    for file in files
      if file is 'base_component.coffee' then continue
      fullPath = nodePath.resolve(__dirname, "../../lib/components/#{file}")
      Component = require fullPath
      component = new Component

      componentName = nodePath.basename file, '.coffee'
      test.notEqual component.namespace, undefined, 'should have a namespace'

  test.end()