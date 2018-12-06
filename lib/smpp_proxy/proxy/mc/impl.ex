defmodule SmppProxy.Proxy.MC.Impl do
  @moduledoc """
  An implementation of logic behind proxy MC session (`SmppProxy.Proxy.MC.Session`).
  """

  alias SMPPEX.Pdu
  alias SmppProxy.{Config, FactoryHelpers}
  alias SmppProxy.Proxy.PduStorage

  require Logger

  @doc """
  Handles pdu from ESME when ProxyMC session is bound (has corresponding ProxyESME session).
  """
  @spec handle_pdu_from_esme_in_bound_state(pdu :: Pdu.t(), pdu_storage :: pid, proxy_esme :: pid, config :: Config.t()) ::
          {:ok, :proxied} | {:error, Pdu.t() | :unknown_pdu}

  def handle_pdu_from_esme_in_bound_state(pdu, pdu_storage, proxy_esme, %Config{} = config) do
    if allowed_to_proxy?(pdu, config) do
      PduStorage.store(pdu_storage, pdu)
      SMPPEX.Session.send_pdu(proxy_esme, pdu)
      {:ok, :proxied}
    else
      case FactoryHelpers.build_response_pdu(pdu, :RINVSRCADR) do
        {:ok, resp} ->
          {:error, resp}

        {:error, _} ->
          {:error, :unknown_pdu}
      end
    end
  end

  @doc """
  Handles pdu from ESME when ProxyMC session is unbound (does not have corresponding ProxyESME session).
  Expects bind request.
  """
  @spec handle_pdu_from_esme_in_unbound_state(pdu :: Pdu.t(), config :: Config.t()) ::
          {:ok, :proxied} | {:error, Pdu.t() | :unknown_pdu}

  def handle_pdu_from_esme_in_unbound_state(pdu, %Config{} = config) do
    if Pdu.command_name(pdu) == Config.bind_command_name(config) && bind_account_matches?(pdu, config) do
      {:ok, proxy_esme_session} = SmppProxy.Proxy.ESME.start_session({self(), config})

      :ok =
        SMPPEX.Session.send_pdu(
          proxy_esme_session,
          apply(Pdu.Factory, Config.bind_command_name(config), [config.esme_system_id, config.esme_password])
        )

      {:ok, proxy_esme_session}
    else
      {:ok, bind_resp} = FactoryHelpers.build_response_pdu(pdu, :RBINDFAIL)
      {:error, bind_resp}
    end
  end

  # def handle_resp_from_esme(proxy_esme_bound, pdu, original_pdu, mc_session) do
  # end

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
        {:ok, bind_resp} =
          FactoryHelpers.build_response_pdu(proxy_mc_bind_pdu, 0, [Pdu.field(proxy_mc_bind_pdu, :system_id)])

      err ->
        Logger.warn(fn -> "ProxyESME->MC bind error: #{Pdu.Errors.description(err)}" end)

        {:ok, bind_resp} =
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
