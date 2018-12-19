# Nodelet

Duplex remote calls between Elixir and Node.JS over Port.

The wrapper uses stdio to communicate to erlang, so *dont* use `console.log(..)`.

## Getting Started

### Nodelet Interface

example.js
```js
const server = require('nodelet');
const bus = require('./message_bus.js');

const bus_port = 1234;

// an example of request handler
server.send_msg = (text) => {
  bus.publish('my-topic', text);
}

bus.on('connect', () => {
  server.info('bus connected', { bus_port });
  // REQUIRED: init the elixir Nodelet
  server.ready();
});

bus.on('data', (text) => {
  // make a request back to elixir handler
  await server.call('recv_msg', text);
});

bus.on('error', () => {
  server.error('bus error');
  server.close();
});

server.on('end', () => {
  // hook into graceful shutdown
  bus.close();
});

server.debug('this will print to stderr');
// disabled during production

bus.connect({ port: bus_port });
```

example.ex
```elixir
defmodule Nodelet.Example do
  require Logger

  @name :example

  # create atoms used in logging meta from nodelet
  @meta [:bus_port]

  def start_link() do
    opts = %{ application: MyProject, module: "example.js", handler: __MODULE__ }
    Nodelet.start_link(opts, name: @name)
  end

  def send_msg(text) do
    Logger.info "send msg #{text}"
    # call the node request handler 'send_msg'
    Nodelet.call(@name, "send_msg", text)
  end

  # handler for the request which orginated from node
  def recv_msg(text) do
    Logger.info "recv msg #{text}"
  end
end
```

application.ex
```elixir
defmodule MyProject.Application do
  use Application

  def start(_type, _args) do
    children = [Nodelet.Example]
    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## TODO

- [ ] Figure out how to open fd 3 and 4 in node to allow stdio for debugging
- [ ] Test async requests in both directions with no conflicts
- [ ] Ensure graceful shutdown in all failure cases
- [ ] Write a `gen_server.js` alternative to `nodelet.js`
