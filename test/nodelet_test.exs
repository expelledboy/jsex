defmodule Jsex.Nodelet.Test do
  use ExUnit.Case, async: false
  import Mock
  alias Jsex.Nodelet

  @handler Handler
  @opts %{module_path: File.cwd!() <> "/test", module: "nodelet.mock.js", handler: @handler}

  test "make request to stateful node process" do
    {:ok, nodelet} = Nodelet.start_link(@opts)
    assert {:ok, [1]} = Nodelet.call(nodelet, "count")
  end

  test "node process can send requests" do
    {:ok, nodelet} = Nodelet.start_link(@opts)

    with_mock @handler, [:non_strict], state_equal: fn st -> st end do
      {:ok, [true]} = Nodelet.call(nodelet, "do_call")
      assert :ok = :meck.wait(1, @handler, :state_equal, 1, 1000)
      assert_called(@handler.state_equal(0))
    end
  end

  test "allow node process to terminate gracefully" do
    Process.sleep(10)
    File.rm("/tmp/terminate")
    assert not File.exists?("/tmp/terminate")

    spawn(fn ->
      {:ok, nodelet} = Nodelet.start_link(@opts)
      Process.exit(nodelet, :shutdown)
    end)

    assert file_created?("/tmp/terminate")
  end

  defp file_created?(file, timeout \\ 1000) do
    timeout = timeout - 10
    Process.sleep(10)
    if(File.exists?(file), do: true, else: file_created?(file, timeout))
  end
end
