defmodule SmppProxy.Proxy.MC do
  @moduledoc """
  Proxy MC public interface.
  """

  require Logger

  @doc "Starts ProxyMC with given `SmppProxy.Config`."
  @spec start(%{config: SmppProxy.Config.t(), rate_limiter: nil | pid}) :: {:ok, pid}

  def start(%{config: %SmppProxy.Config{} = config, rate_limiter: _} = args) do
    {:ok, mc} = SMPPEX.MC.start({SmppProxy.Proxy.MC.Session, args}, transport_opts: [port: config.mc_port])

    Logger.info(fn ->
      "Ready to accept connections on #{config.mc_port} with #{config.mc_system_id}/#{config.mc_password}"
    end)

    {:ok, mc}
  end

  @doc """
  Proxies MC resp. Chain is MC->ProxyESME->ProxyMC->ESME.
  """
  @spec handle_mc_resp(proxy_mc_session :: pid, pdu :: Pdu.t(), proxy_esme_original_pdu :: Pdu.t()) :: term

  def handle_mc_resp(proxy_mc_session, pdu, proxy_esme_original_pdu) do
    SMPPEX.Session.call(proxy_mc_session, {:handle_mc_resp, pdu, proxy_esme_original_pdu})
  end
end
