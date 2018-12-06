defmodule SmppProxy.Proxy.MC.Impl do
  @moduledoc """
  An implementation of logic behind proxy MC session (`SmppProxy.Proxy.MC.Session`).
  """

  alias SMPPEX.Pdu
  alias SmppProxy.{Config, FactoryHelpers}
  alias SmppProxy.Proxy.PduStorage

  require Logger

  @doc "Proxies Pdu. ESME -> ProxyMC -> ProxyESME -> MC"
  @spec proxy_pdu(pdu :: Pdu.t(), pdu_storage :: pid, proxy_esme :: pid, config :: Config.t()) ::
          {:ok, :proxied} | {:error, Pdu.t() | :unknown_pdu}

  def proxy_pdu(pdu, pdu_storage, proxy_esme, %Config{} = config) do
    if allowed_to_proxy?(pdu, config) do
      PduStorage.store(pdu_storage, pdu)
      SMPPEX.Session.send_pdu(proxy_esme, pdu)

      {:ok, :proxied}
    else
      {:error, FactoryHelpers.build_response_pdu(pdu, :RINVSRCADR)}
    end
  end

  @doc "Handles ESME->ProxyMC bind request."
  @spec handle_bind_request(pdu :: Pdu.t(), config :: Config.t()) :: {:ok, :proxied} | {:error, Pdu.t() | :unknown_pdu}

  def handle_bind_request(pdu, %Config{} = config) do
    if Pdu.command_name(pdu) == Config.bind_command_name(config) && bind_account_matches?(pdu, config) do
      {:ok, proxy_esme_session} = SmppProxy.Proxy.ESME.start_session({self(), config})

      mc_bind_pdu =
        pdu
        |> Pdu.set_mandatory_field(:system_id, config.esme_system_id)
        |> Pdu.set_mandatory_field(:password, config.esme_password)

      :ok = SMPPEX.Session.send_pdu(proxy_esme_session, mc_bind_pdu)

      {:ok, proxy_esme_session}
    else
      {:error, FactoryHelpers.build_response_pdu(pdu, :RBINDFAIL)}
    end
  end

  @doc """
  Handles MC response.
  """
  @spec handle_mc_resp(pdu :: Pdu.t(), esme_original_pdu :: Pdu.t(), pdu_storage :: pid) :: {:ok, Pdu.t()}

  def handle_mc_resp(pdu, esme_original_pdu, pdu_storage) do
    original_pdu = PduStorage.fetch(pdu_storage, esme_original_pdu.ref)
    resp = Pdu.as_reply_to(pdu, original_pdu)
    PduStorage.delete(pdu_storage, original_pdu.ref)

    {:ok, resp}
  end

  @doc """
  Handles MC bind response.
  """
  @spec handle_mc_bind_resp(pdu :: Pdu.t(), proxy_mc_bind_pdu :: Pdu.t()) :: {:ok, Pdu.t()} | {:error, Pdu.t()}

  def handle_mc_bind_resp(pdu, proxy_mc_bind_pdu) do
    case Pdu.command_status(pdu) do
      0 ->
        bind_resp = FactoryHelpers.build_response_pdu(proxy_mc_bind_pdu, 0, [Pdu.field(proxy_mc_bind_pdu, :system_id)])
        {:ok, bind_resp}

      err ->
        Logger.warn(fn -> "ProxyESME->MC bind error: #{Pdu.Errors.description(err)}" end)

        bind_resp =
          FactoryHelpers.build_response_pdu(proxy_mc_bind_pdu, :RBINDFAIL, [Pdu.field(proxy_mc_bind_pdu, :system_id)])

        {:error, bind_resp}
    end
  end

  defp bind_account_matches?(bind_pdu, %{mc_system_id: id, mc_password: pwd}) do
    Pdu.field(bind_pdu, :system_id) == id && Pdu.field(bind_pdu, :password) == pwd
  end

  defp allowed_to_proxy?(%{mandatory: %{source_addr: source, destination_addr: dest}}, %{
         senders_whitelist: sw,
         receivers_whitelist: rw
       }) do
    (sw == [] || source in sw) && (rw == [] || dest in rw)
  end

  defp allowed_to_proxy?(_pdu, _config), do: true
end
