[![Attak Distributed Computing Framework](./lib/img/readme.png)](http://attak.io)

*The best way to orchestrate multiple serverless processors in a robus, debuggable way*

ATTAK is a framework that helps you string together "serverless" functions and message queues to create distributed compute topologies. It aims to be platform agnostic, beginning with support for AWS and Google Cloud.

## Contents

* [Quick Start](#quick-start)
* [Examples](#examples)
* [Docs](https://attak.github.io/docs)

## <a name="quick-start"></a>Quick Start

### Install cli

`npm install -g attak`

### Create an attak topology

Generate a simple boilerplate project by running:

`attak init`

### Setup environment

Rename `.env.example` to `.env` and put in values as appropriate for your deploy. The required fields are:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ROLE_ARN`

### Topology simulation and debugging

Visit [the ATTAK ui](http://attak.io#local) and run the simulation with the command displayed, which will look like:

`attak simulate -i [simulation id]`

If you want to run the topology without the UI debugger, simply run

`attak simulate` 

### Deploy the topology

ATTAK will deploy all processors and streams in the topology.

```attak deploy```

## <a name="examples"></a>Examples

- [Simple hello world](http://github.com/attak/attak-hello-world) - Emit some text and reverse it
- [Stream github events](http://github.com/attak/attak-github-events) - Monitor the GitHub Events API for updates and process the results
