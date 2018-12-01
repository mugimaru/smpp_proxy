defmodule SmppProxy.Proxy do
  use GenServer
  require Logger

  def start_link(opts) do
    Logger.debug(fn -> "Starting SMPP proxy..." end)
    GenServer.start_link(__MODULE__, opts)
  end

  def init(%SmppProxy.Config{mc_port: mc_port} = opts) do
    {:ok, mc} = SMPPEX.MC.start({SmppProxy.Proxy.MCSession, opts}, transport_opts: [port: mc_port])
    Logger.info(fn -> "Ready to accept connections on #{mc_port} with #{opts.mc_system_id}/#{opts.mc_password}" end)
    {:ok, Map.put(opts, :mc, mc)}
  end

  def terminate(_reason, state) do
    :ok = SMPPEX.MC.stop(state.mc)
    :stop
  end

  def allowed_to_proxy?(%{senders_whitelist: sw, receivers_whitelist: rw}, sender: s, receiver: r) do
    (sw == [] || s in sw) && (rw == [] || r in rw)
  end
end
