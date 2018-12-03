defmodule SmppProxy.Proxy.ESME do
  @moduledoc """
  Proxy ESME public interface.
  """
  alias __MODULE__.Session
  alias SMPPEX.Pdu

  @doc "Starts proxy ESME session. See `SmppProxy.Proxy.ESME.Session.start_link/1`."
  @spec start_session({mc_pid :: pid, config :: SmppProxy.Config.t()}) :: term

  def start_session({mc_pid, %SmppProxy.Config{} = config}) do
    Session.start_link({mc_pid, config})
  end

  @doc """
  Proxies ESME response to target MC.
  """
  @spec proxy_esme_resp(proxy_esme_session :: pid, pdu :: Pdu.t(), proxy_mc_original_pdu :: Pdu.t()) :: :ok

  def proxy_esme_resp(proxy_esme_session, pdu, proxy_mc_original_pdu) do
    :ok = SMPPEX.Session.call(proxy_esme_session, {:proxy_esme_resp, pdu, proxy_mc_original_pdu})
  end
end
