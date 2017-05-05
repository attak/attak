#!/usr/bin/env node
require('coffee-script/register');

var fs = require('fs');
var dotenv = require('dotenv');
var SimulationUtils = require('../lib/simulation/simulation')
var ATTAK = require('../lib/attak');

var packageJson = fs.existsSync(process.cwd() + '/package.json') ? require(process.cwd() + '/package.json') : {};
var packageJsonName = packageJson.name || 'UnnamedFunction';

dotenv.load();

var AWS_ENVIRONMENT = process.env.AWS_ENVIRONMENT || '';
var CONFIG_FILE = process.env.CONFIG_FILE || '';
var EXCLUDE_GLOBS = process.env.EXCLUDE_GLOBS || '';
var AWS_ACCESS_KEY_ID = process.env.AWS_ACCESS_KEY_ID;
var AWS_SECRET_ACCESS_KEY = process.env.AWS_SECRET_ACCESS_KEY;
var AWS_PROFILE = process.env.AWS_PROFILE || '';
var AWS_SESSION_TOKEN = process.env.AWS_SESSION_TOKEN || '';
var AWS_REGION = process.env.AWS_REGION || 'us-east-1,us-west-2,eu-west-1';
var AWS_FUNCTION_NAME = process.env.AWS_FUNCTION_NAME || packageJsonName;
var AWS_HANDLER = process.env.AWS_HANDLER || 'index.handler';
var AWS_ROLE = process.env.AWS_ROLE_ARN || process.env.AWS_ROLE || 'missing';
var AWS_MEMORY_SIZE = process.env.AWS_MEMORY_SIZE || 128;
var AWS_TIMEOUT = process.env.AWS_TIMEOUT || 60;
var AWS_RUN_TIMEOUT = process.env.AWS_RUN_TIMEOUT || 3;
var AWS_DESCRIPTION = process.env.AWS_DESCRIPTION || packageJson.description || '';
var AWS_RUNTIME = process.env.AWS_RUNTIME || 'nodejs4.3';
var AWS_PUBLISH = process.env.AWS_PUBLISH || false;
var AWS_FUNCTION_VERSION = process.env.AWS_FUNCTION_VERSION || '';
var AWS_VPC_SUBNETS = process.env.AWS_VPC_SUBNETS || '';
var AWS_VPC_SECURITY_GROUPS = process.env.AWS_VPC_SECURITY_GROUPS || '';
var INPUT_FILE = process.env.INPUT_FILE || 'input.json';
var PACKAGE_DIRECTORY = process.env.PACKAGE_DIRECTORY;
var CONTEXT_FILE = process.env.CONTEXT_FILE || 'context.json';
var PREBUILT_DIRECTORY = process.env.PREBUILT_DIRECTORY || '';
var LOGIN_NAME = process.env.LOGIN_NAME || '';
var LOCAL_DYNAMO = process.env.LOCAL_DYNAMO || packageJson.dynamo || false

var close = function(err) {
  if (err) {
    console.log("CAUGHT ERR", err)
  }
  setTimeout(function() {
    process.exit()
  }, 500)
}

require('yargs')
  .command('deploy', 'Deploy an ATTAK topology', function(yargs) {
    yargs.option('environment', {alias: 'e', default: AWS_ENVIRONMENT})
    yargs.option('accessKey', {alias: 'a', default: AWS_ACCESS_KEY_ID})
    yargs.option('secretKey', {alias: 's', default: AWS_SECRET_ACCESS_KEY})
    yargs.option('profile', {alias: 'P', default: AWS_PROFILE})
    yargs.option('sessionToken', {alias: 'k', default: AWS_SESSION_TOKEN})
    yargs.option('region', {alias: 'r', default: AWS_REGION})
    yargs.option('handler', {alias: 'H', default: AWS_HANDLER})
    yargs.option('role', {alias: 'o', default: AWS_ROLE})
    yargs.option('memorySize', {alias: 'm', default: AWS_MEMORY_SIZE})
    yargs.option('timeout', {alias: 't', default: AWS_TIMEOUT})
    yargs.option('description', {alias: 'd', default: AWS_DESCRIPTION})
    yargs.option('runtime', {alias: 'u', default: AWS_RUNTIME})
    yargs.option('publish', {alias: 'p', default: AWS_PUBLISH})
    yargs.option('lambdaVersion', {alias: 'L', default: AWS_FUNCTION_VERSION})
    yargs.option('vpcSubnets', {alias: 'b', default: AWS_VPC_SUBNETS})
    yargs.option('vpcSecurityGroups', {alias: 'g', default: AWS_VPC_SECURITY_GROUPS})
    yargs.option('packageDirectory', {alias: 'A', default: PACKAGE_DIRECTORY})
    yargs.option('configFile', {alias: 'f', default: CONFIG_FILE})
    yargs.option('excludeGlobs', {alias: 'x', default: EXCLUDE_GLOBS})
    yargs.option('prebuiltDirectory', {alias: 'D', default: PREBUILT_DIRECTORY})
    return yargs
  }, function(argv) {
    ATTAK.deploy(argv, close);
  })
  .command('init', 'Create scaffolding for a new attak project', function(yargs) {
    return yargs
  }, function(argv) {
    ATTAK.init(argv, close);
  })
  .command('simulate', 'Simulate an attak topology by running it locally', function(yargs) {
    yargs.option('dynamo', {alias: 'dy', default: LOCAL_DYNAMO})
    yargs.option('inputFile', {alias: 'j', default: INPUT_FILE})
    yargs.option('id', {alias: 'i', default: LOGIN_NAME})
    return yargs
  }, function(argv) {
    SimulationUtils.setupAndRun(argv, close);
  })
  .command('trigger', 'Simulate an attak topology by running it locally', function(yargs) {
    yargs.option('region', {alias: 'r', default: AWS_REGION})
    yargs.option('inputFile', {alias: 'j', default: INPUT_FILE})
    yargs.option('environment', {alias: 'e', default: AWS_ENVIRONMENT})
    return yargs
  }, function(argv) {
    ATTAK.simulate(argv, close);
  })
  .argv
