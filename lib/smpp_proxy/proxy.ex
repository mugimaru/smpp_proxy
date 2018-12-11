defmodule SmppProxy.Proxy do
  use GenServer
  require Logger

  defstruct [:config, :mc, :rate_limiter]

  @spec start_link(config :: SmppProxy.Config.t()) :: term
  def start_link(%SmppProxy.Config{} = config) do
    Logger.debug(fn -> "Starting SMPP proxy with #{inspect(config)}" end)
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(%SmppProxy.Config{} = config) do
    rate_limiter = maybe_start_rate_limiter(config.rate_limit)
    {:ok, mc} = SmppProxy.Proxy.MC.start(%{config: config, rate_limiter: rate_limiter})

    {:ok, struct(__MODULE__, config: config, mc: mc, rate_limiter: rate_limiter)}
  end

  @impl true
  def terminate(_reason, state) do
    :ok = SMPPEX.MC.stop(state.mc)
    :stop
  end

  defp maybe_start_rate_limiter(nil), do: nil

  defp maybe_start_rate_limiter({n, interval}) do
    {:ok, pid} = SmppProxy.RateLimiter.start_link(n, interval)
    pid
  end
end
