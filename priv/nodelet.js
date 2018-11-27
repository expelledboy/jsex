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

function send(data) {
  const output = JSON.stringify(data);
  console.log(output);
}

const handler = {

  request: (args) => {
    const [ref, action, ...params] = args;
    // if this errors should crash the nodelet
    if (!server[action]) throw new Error(`undefined function ${action}`);
    const response = server[action](...params);
    send(['response', ref, response]);
  },

  response: (args) => {
    const [ref, ...params] = args;
    requests[ref](...params);
    delete requests[ref];
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

async function call(action, ...args) {
  const ref = Math.random() * 10000000000000000000;
  send(['request', ref, action, ...args]);
  return await recieve(ref);
}

function online() {
  this.emit('online');
  call('online');
}

function offline() {
  this.emit('offline');
  call('offline');
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

function init(ready = true) {
  this.emit('init');
  readLineInterface.on('line', handle);
  send(['init', ready]);
  this.emit(ready ? 'online' : 'offline');
}

function log(type) {
  return (msg, meta = {}) => {
    if (!meta instanceof Object) throw new Error(`invalid meta used for logging`);
    send([type, msg, meta]);
  };
}

function debug(msg) {
  // XXX follow Logger standards
  const datetime = new Date().toISOString();
  const time = datetime.split(new RegExp('T|Z'))[1];
  console.error(time, '[debug]', msg);
}

Object.assign(server, {
  call,
  online,
  offline,
  init,
  debug,
  info: log('info'),
  warn: log('warn'),
  error: log('error'),
});

if (process.env['MIX_ENV'] == 'prod') Object.assign(server, {
  debug: () => {},
});

module.exports = server;
