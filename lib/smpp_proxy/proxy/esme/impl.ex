defmodule SmppProxy.Proxy.ESME.Impl do
  @moduledoc """
  * `MC` - target message center;
  * `ESME` - client that binds to proxy app in order to send messages to `MC`;
  * `Proxy MC` - message center of proxy app;
  * `Proxy ESME` - client that binds to `MC`;
  """

  alias SMPPEX.{Pdu, RawPdu, Session}
  alias SmppProxy.{Config, FactoryHelpers}
  alias SmppProxy.Proxy.PduStorage

  @doc """
  Checks if proxy ESME is allowed to proxy specific pdu.
  """
  @spec allowed_to_proxy?(Pdu.t(), Config.t()) :: boolean

  def allowed_to_proxy?(%{mandatory: %{source_addr: source, destination_addr: dest}}, config) do
    SmppProxy.Proxy.allowed_to_proxy?(config, sender: dest, receiver: source)
  end

  def allowed_to_proxy?(_pdu, _config), do: true


  @doc """
  Attempts to proxy pdu from MC to ESME.
  """
  @spec handle_pdu_from_mc(Pdu.t() | RawPdu.t(), %{pdu_storage: pid, mc_session: pid, config: Config.t()}) :: {:ok, :proxied} | {:error, Pdu.t()} | {:error, :unknown_pdu}

  def handle_pdu_from_mc(pdu, %{pdu_storage: pdu_storage, mc_session: mc_session, config: config}) do
    if allowed_to_proxy?(pdu, config) do
      PduStorage.store(pdu_storage, pdu)
      Session.send_pdu(mc_session, pdu)

      {:ok, :proxied}
    else
      case FactoryHelpers.build_response_pdu(pdu, 0) do
        {:ok, resp} ->
          {:error, resp}

        {:error, _} ->
          {:error, :unknown_pdu}
      end
    end
  end

  @doc "Handles response pdu from MC."
  @spec handle_resp_from_mc(resp_pdu :: Pdu.t(), original_pdu :: Pdu.t(), mc_session :: pid) :: :ok

  def handle_resp_from_mc(pdu, original_pdu, mc_session) do
    if SMPPEX.Pdu.command_name(pdu) in [:bind_transceiver_resp, :bind_transmitter_resp, :bind_receiver_resp] do
      :ok = Session.call(mc_session, {:esme_bind_resp, pdu})
    else
      :ok = Session.call(mc_session, {:proxy_resp, pdu, original_pdu})
    end
  end

  @doc "Handles response pdu from ESME."
  @spec handle_resp_from_esme(pdu :: Pdu.t(), esme_original_pdu :: Pdu.t(), pdu_storage :: pid) :: {:ok, Pdu.t()}

  def handle_resp_from_esme(pdu, esme_original_pdu, pdu_storage) do
    original_pdu = PduStorage.fetch(pdu_storage, esme_original_pdu.ref)
    resp = Pdu.as_reply_to(pdu, original_pdu)
    PduStorage.delete(pdu_storage, original_pdu.ref)

    {:ok, resp}
  end
end
