#!/usr/bin/env node
require('coffee-script/register');

var fs = require('fs');
var dotenv = require('dotenv');
var attak = require('../lib/main');
var program = require('commander');

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

var close = function() {
  setTimeout(function() {
    process.exit()
  }, 500)
}

program
  .command('deploy')
  .version(attak.version)
  .description('Deploy your attak application to Amazon Lambda')
  .option('-e, --environment [' + AWS_ENVIRONMENT + ']', 'Choose environment {dev, staging, production}', AWS_ENVIRONMENT)
  .option('-a, --accessKey [' + AWS_ACCESS_KEY_ID + ']', 'AWS Access Key', AWS_ACCESS_KEY_ID)
  .option('-s, --secretKey [' + AWS_SECRET_ACCESS_KEY + ']', 'AWS Secret Key', AWS_SECRET_ACCESS_KEY)
  .option('-P, --profile [' + AWS_PROFILE + ']', 'AWS Profile', AWS_PROFILE)
  .option('-k, --sessionToken [' + AWS_SESSION_TOKEN + ']', 'AWS Session Token', AWS_SESSION_TOKEN)
  .option('-r, --region [' + AWS_REGION + ']', 'AWS Region', AWS_REGION)
  .option('-n, --functionName [' + AWS_FUNCTION_NAME + ']', 'Lambda FunctionName', AWS_FUNCTION_NAME)
  .option('-H, --handler [' + AWS_HANDLER + ']', 'Lambda Handler {index.handler}', AWS_HANDLER)
  .option('-o, --role [' + AWS_ROLE + ']', 'Amazon Role ARN', AWS_ROLE)
  .option('-m, --memorySize [' + AWS_MEMORY_SIZE + ']', 'Lambda Memory Size', AWS_MEMORY_SIZE)
  .option('-t, --timeout [' + AWS_TIMEOUT + ']', 'Lambda Timeout', AWS_TIMEOUT)
  .option('-d, --description [' + AWS_DESCRIPTION + ']', 'Lambda Description', AWS_DESCRIPTION)
  .option('-u, --runtime [' + AWS_RUNTIME + ']', 'Lambda Runtime', AWS_RUNTIME)
  .option('-p, --publish [' + AWS_PUBLISH + ']', 'Lambda Publish', AWS_PUBLISH)
  .option('-L, --lambdaVersion [' + AWS_FUNCTION_VERSION + ']', 'Lambda Function Version', AWS_FUNCTION_VERSION)
  .option('-b, --vpcSubnets [' + AWS_VPC_SUBNETS + ']', 'Lambda Function VPC Subnets', AWS_VPC_SUBNETS)
  .option('-g, --vpcSecurityGroups [' + AWS_VPC_SECURITY_GROUPS + ']', 'Lambda VPC Security Group', AWS_VPC_SECURITY_GROUPS)
  .option('-A, --packageDirectory [' + PACKAGE_DIRECTORY + ']', 'Local Package Directory', PACKAGE_DIRECTORY)
  .option('-f, --configFile [' + CONFIG_FILE + ']', 'Path to file holding secret environment variables (e.g. "deploy.env")', CONFIG_FILE)
  .option('-x, --excludeGlobs [' + EXCLUDE_GLOBS + ']', 'Space-separated glob pattern(s) for additional exclude files (e.g. "event.json dotenv.sample")', EXCLUDE_GLOBS)
  .option('-D, --prebuiltDirectory [' + PREBUILT_DIRECTORY + ']', 'Prebuilt directory', PREBUILT_DIRECTORY)
  .action(function (prg) {
    attak.deploy(prg, close);
  });

program
  .command('init')
  .description('Create scaffolding for a new attak project')
  .action(function (prg) {
    attak.init(prg, close);
  });

program
  .command('simulate')
  .description('Simulate an attak topology by running it locally')
  .option('-dy, --dynamo', 'Run local dynamodb simulator', LOCAL_DYNAMO)
  .option('-j, --inputFile [' + INPUT_FILE + ']', 'Event JSON File', INPUT_FILE)
  .option('-i, --id [' + LOGIN_NAME + ']', 'Debug session ID (defaults to username)', LOGIN_NAME)
  .action(function (prg) {
    attak.simulate(prg, close);
  });

program
  .command('trigger')
  .description('Trigger one or more streams')
  .option('-r, --region [' + AWS_REGION + ']', 'AWS Region', AWS_REGION)
  .option('-j, --inputFile [' + INPUT_FILE + ']', 'Event JSON File', INPUT_FILE)
  .option('-e, --environment [' + AWS_ENVIRONMENT + ']', 'Choose environment {dev, staging, production}', AWS_ENVIRONMENT)

  .action(function (prg) {
    attak.trigger(prg, close);
  });

program.parse(process.argv);