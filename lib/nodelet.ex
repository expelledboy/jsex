defmodule Jsex.Nodelet do
  use GenServer
  require Logger

  def request(nodelet, action, args \\ []) do
    GenServer.call(nodelet, {:request, action, args})
  end

  def start_link(opts, link_opts \\ []) do
    GenServer.start_link(__MODULE__, opts, link_opts)
  end

  def init(%{module: module} = opts) do
    Process.flag(:trap_exit, true)
    Logger.info("starting nodelet", module: module)

    node = System.find_executable("node")
    app = opts[:application]
    module_path = if(app, do: :code.priv_dir(app), else: opts.module_path)
    nodelet = Path.join(module_path, module)
    path = Enum.join([module_path, :code.priv_dir(:jsex)], ":")

    port =
      Port.open({:spawn_executable, node}, [
        :binary,
        :exit_status,
        # TODO would be nice to allow stdio to console from nodelet
        # but dont know how create specific fd 3,4 in node
        # :nouse_stdio,
        line: 2000,
        # XXX will show up in process.argv
        args: [nodelet | Map.get(opts, :args, [])],
        env: [
          {'NODE_PATH', String.to_charlist(path)}
        ]
      ])

    state = %{
      handler: opts[:handler],
      port: port,
      buffer: "",
      requests: %{}
    }

    :ok = wait_init(port, 3000)
    Logger.debug("nodelet ready")
    {:ok, state}
  end

  defp wait_init(port, timeout) do
    receive do
      {^port, {:data, {:eol, "init"}}} ->
        :ok

      {^port, {:exit_status, status}} ->
        throw({:exit, status})
    after
      timeout ->
        receive do
          msg -> throw({:timeout, last_message: msg})
        after
          0 -> throw(:timeout)
        end
    end
  end

  def terminate(reason, st) do
    Logger.info("stoping nodelet", reason: reason)
    data = Jason.encode!(["terminate"])
    true = Port.command(st.port, "#{data}\n")

    receive do
      {_, {:exit_status, 0}} -> st
    after
      100 -> throw(:terminate_timeout)
    end
  end

  def handle_info({:EXIT, _from, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info({:timeout, ref}, st) do
    Logger.error("request timeout", reference: ref)

    case close_request(ref, st) do
      {:error, :request_not_found} ->
        {:stop, :timeout, st}

      {:ok, from, st} ->
        GenServer.reply(from, {:error, :timeout})
        {:stop, :timeout, st}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = st) do
    Logger.debug("script terminated", status: status)
    reason = if(status == 0, do: :normal, else: {:exit, status})
    {:stop, reason, st}
  end

  def handle_info({port, :closed}, %{port: port} = st) do
    {:stop, :normal, st}
  end

  def handle_info({port, {:data, data}}, %{port: port} = st) do
    case buffer(data, st) do
      {:data, packet, st} ->
        [packet | args] = Jason.decode!(packet)
        handle_data(packet, args, st)

      {:continue, st} ->
        {:noreply, st}
    end
  end

  def handle_call({:request, action, args}, from, st) do
    ref = make_ref() |> :erlang.ref_to_list() |> to_string
    data = Jason.encode!(["request", ref, action] ++ args)
    Logger.debug("sending request", reference: ref)

    case Port.command(st.port, "#{data}\n") do
      true ->
        {:noreply, open_request(ref, from, st)}

      false ->
        {:stop, :port_closed, st}
    end
  end

  defp handle_data("request", [ref, action | args], st) do
    Logger.debug("got request", reference: ref)
    if is_nil(st.handler), do: throw(:handler_undefined)
    function_name = String.to_existing_atom(action)
    response = apply(st.handler, function_name, args)
    data = Jason.encode!(["response", ref, response])
    Logger.debug("sending response", reference: ref)

    case Port.command(st.port, "#{data}\n") do
      true ->
        {:noreply, st}

      false ->
        {:stop, :port_closed, st}
    end
  end

  defp handle_data("response", [ref | args], st) do
    Logger.debug("got response", reference: ref)

    case close_request(ref, st) do
      {:error, :request_not_found} ->
        {:stop, :unhandled_request, st}

      {:ok, from, st} ->
        GenServer.reply(from, {:ok, args})
        {:noreply, st}
    end
  end

  defp handle_data(log, [msg, meta], st) when log in ["info", "warn", "error"] do
    Logger.log(
      String.to_existing_atom(log),
      msg,
      to_keyword_list(meta)
    )
    {:noreply, st}
  end

  defp open_request(ref, from, st) do
    timer_ref = Process.send_after(self(), {:timeout, ref}, 3000)
    Map.update!(st, :requests, &Map.put(&1, ref, {timer_ref, from}))
  end

  defp close_request(ref, st) do
    case Map.pop(st.requests, ref) do
      {nil, _} ->
        {:error, :request_not_found}

      {{timer_ref, from}, requests} ->
        Process.cancel_timer(timer_ref)
        {:ok, from, Map.put(st, :requests, requests)}
    end
  end

  defp buffer({:noeol, partial}, st) do
    {:continue, %{st | buffer: partial <> st.buffer}}
  end

  defp buffer({:eol, partial}, st) do
    {:data, partial <> st.buffer, %{st | buffer: ""}}
  end

  defp to_keyword_list(dict) do
    # XXX rather safe than sorry
    Enum.map(dict, fn({key, value}) -> {String.to_existing_atom(key), value} end)
  end
end
