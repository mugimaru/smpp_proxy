defmodule SmppProxy.Proxy do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(%{mc_port: mc_port} = opts) do
    {:ok, mc} = SMPPEX.MC.start({SmppProxy.Proxy.MCSession, opts}, transport_opts: [port: mc_port])
    {:ok, Map.put(opts, :mc, mc)}
  end

  def terminate(_reason, state) do
    :ok = SMPPEX.MC.stop(state.mc)
    :stop
  end
end
