defmodule SmppProxy.Proxy.MC do
  @moduledoc """
  Proxy MC public interface.
  """

  require Logger

  @doc "Starts ProxyMC with given `SmppProxy.Config`."
  @spec start(config :: SmppProxy.Config.t()) :: {:ok, pid}

  def start(%SmppProxy.Config{} = config) do
    {:ok, mc} = SMPPEX.MC.start({SmppProxy.Proxy.MC.Session, config}, transport_opts: [port: config.mc_port])

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
