const readline = require('readline');
const EventEmitter = require('events').EventEmitter;

const server = new EventEmitter();

// list of open requests
const requests = [];

// XXX fail fast, handle in elixir supervision tree
process.on('unhandledRejection', err => { throw err });

process.stdin.on('end', () => process.exit())

const readLineInterface = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
})

const handler = {

  request: (args) => {
    const [ref, action, ...params] = args;
    // if this errors should crash the nodelet
    const response = server[action](...params);
    const output = JSON.stringify(['response', ref, response]);
    console.log(output);
  },

  response: (args) => {
    const [ref, ...params] = args;
    requests[ref](...params);
  },

  terminate: () => {
    // XXX this should be the last subsriber of the event installed
    server.on('end', () => readLineInterface.close());
    server.emit('end');
  },

};

async function handle(input) {
  const [packet, ...args] = JSON.parse(input)
  handler[packet](args);
}

async function request(action, ...args) {
  const ref = Math.random() * 10000000000000000000;
  const output = JSON.stringify(['request', ref, action, ...args]);
  console.log(output);
  return await recieve(ref);
}

async function recieve(ref) {
  return new Promise((resolve, reject) => {
    requests[ref] = resolve;
    setTimeout(() => {
      // XXX if the promise was already resolved this will do nothing
      reject(new Error(`request timeout - ${ref}`));
    }, 3000);
  });
}

function ready() {
  this.emit('ready');
  readLineInterface.on('line', handle)
  // XXX this is the only message that does not conform to the stdio message protocol
  console.log('init');
}

Object.assign(server, {
  request,
  ready,
});

module.exports = server;
