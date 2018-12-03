defmodule SmppProxy.Proxy do
  use GenServer
  require Logger

  defstruct [:config, :mc]

  @spec start_link(config :: SmppProxy.Config.t()) :: term
  def start_link(%SmppProxy.Config{} = config) do
    Logger.debug(fn -> "Starting SMPP proxy..." end)
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(%SmppProxy.Config{} = config) do
    {:ok, mc} = SmppProxy.Proxy.MC.start(config)
    {:ok, struct(__MODULE__, config: config, mc: mc)}
  end

  @impl true
  def terminate(_reason, state) do
    :ok = SMPPEX.MC.stop(state.mc)
    :stop
  end
end
