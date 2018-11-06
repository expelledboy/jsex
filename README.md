# Jsex

Duplex remote calls between Elixir and Node.JS over Port.

The wrapper uses stdio to communicate to erlang, so avoid `console.log(...)`.

## Getting Started

example.js
```js
const server = require('nodelet');
const bus = require('./message_bus.js');

// an example of request handler
server.send_msg = (text) => {
  bus.publish('my-topic', text);
}

bus.on('connect', () => {
  // REQUIRED: init the elixir Nodelet
  server.ready();
});

bus.on('data', (text) => {
  // make a request back to elixir handler
  await server.request('recv_msg', text);
});

server.on('end', () => {
  // hook into graceful shutdown
  bus.close();
});

bus.connect({ port: 1234 });
```

example.ex
```elixir
defmodule Nodelet.Example do
  require Logger
  alias Jsex.Nodelet

  @name :example

  def start_link() do
    opts = %{ application: MyProject, module: "example.js", handler: __MODULE__ }
    Nodelet.start_link(opts, name: @name)
  end

  def send_msg(text) do
    Logger.info "send msg #{text}"
    # call the node request handler 'send_msg'
    Nodelet.request(@name, "send_msg", text)
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
- [ ] Write a `gen_server.js` alternative to `nodelet.js`
- [ ] Test async requests in both directions with no conflicts
- [ ] Ensure graceful shutdown in all failure cases
