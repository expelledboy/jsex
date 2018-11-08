const server = require('nodelet');
const fs = require('fs');

function touchFile(filename) {
  fs.closeSync(fs.openSync(filename, 'w'));
}

let state;

setTimeout(() => {
  state = 0;
  server.ready();
}, 20);

// api which we can call from erlang
server.count = () => {
  server.info('calling count', { count: state });
  return state += 1;
}

server.do_request = () => {
  setTimeout(async () => {
    // call from node to server
    server.debug('doing async request to elixir code');
    const response = await server.request('state_equal', state);
    if (response != state) throw new Error('states not equal');
  }, 20);
  return true;
}

server.on('end', () => {
  server.error('terminating nodelet');
  touchFile('/tmp/terminate');
});
