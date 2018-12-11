defmodule SmppProxy.Proxy.MC.Impl do
  @moduledoc """
  An implementation of logic behind proxy MC session (`SmppProxy.Proxy.MC.Session`).
  """

  alias SMPPEX.{Pdu, Protocol.CommandNames}
  alias SmppProxy.{Config, FactoryHelpers}
  alias SmppProxy.Proxy.PduStorage

  require Logger

  @bind_command_ids [:bind_transceiver, :bind_transmitter, :bind_receiver]
                    |> Enum.map(&(CommandNames.id_by_name(&1) |> elem(1)))
  @bind_resp_command_ids [:bind_transceiver_resp, :bind_transmitter_resp, :bind_receiver_resp]
                         |> Enum.map(&(CommandNames.id_by_name(&1) |> elem(1)))

  @doc """
  Proxies Pdu from proxy client (ESME) to proxy target (MC).

  Sends pdu to proxy target (MC) if pdu can be proxied and returns `{:ok, :proxied}`.
  Returns `{:error, response_pdu}` if pdu haven't passed senders/receivers whitelist checks.

  ### Whitelist checks

  Whitelist checks are only applied to the pdus with source/dest address fields (see `SmppProxy.Config` :senders_whitelist and `:receivers_whitelist`).
   * source address must be in senders_whitelist if senders_whitelist is not empty.
   * destination address must be in receivers_whitelist if senders_whitelist is not empty.
  """
  @spec proxy_pdu(pdu :: Pdu.t(), pdu_storage :: pid, proxy_esme :: pid, config :: Config.t()) ::
          {:ok, :proxied} | {:error, Pdu.t()}

  def proxy_pdu(pdu, pdu_storage, proxy_esme, %Config{} = config) do
    if allowed_to_proxy?(pdu, config) do
      PduStorage.store(pdu_storage, pdu)
      SMPPEX.Session.send_pdu(proxy_esme, pdu)
      Logger.debug(fn -> "  " <> "ProxyESME->MC " <> SmppProxy.PduPrinter.format(pdu) end)
      {:ok, :proxied}
    else
      {:error, FactoryHelpers.build_response_pdu(pdu, :RINVSRCADR)}
    end
  end

  @doc """
  Handles ESME->ProxyMC bind request.

  This function is aimed to handle any incomming pdu when ProxyMC is unbound.

  After ESME (proxy client) has sent a bind request we are checking that system_id/password
  of the bind pdu match configuration and attempting to start and bind correlated ProxyESME (which connects to the proxy target aka MC).

  Function returns `{:ok, proxy_esme_pid}` in case of success or `{:error, bind_resp_error_pdu}` (with "bind failed" status) in case of failure.
  Proxy preserves original bind pdu parameters by changing only system_id and password
  (in the most cases sequence number will also be changed, but `SMPPEX` handles it for us).
  """
  @spec handle_bind_request(proxy_mc :: pid, pdu :: Pdu.t(), config :: Config.t()) :: {:ok, pid} | {:error, Pdu.t()}

  def handle_bind_request(proxy_mc_pid, %Pdu{command_id: cid} = pdu, %Config{} = config)
      when cid in @bind_command_ids do
    if bind_account_matches?(pdu, config.mc_system_id, config.mc_password) do
      start_and_bind_proxy_esme(proxy_mc_pid, pdu, config)
    else
      {:error, FactoryHelpers.build_response_pdu(pdu, :RBINDFAIL)}
    end
  end

  def handle_bind_request(_proxy_mc_pid, pdu, _config) do
    {:error, FactoryHelpers.build_response_pdu(pdu, :RBINDFAIL)}
  end

  @doc """
  Handles proxy target (MC) response pdu.

  Returns:
    * `{:bind_error, bind_resp_pdu}` if `pdu` is a bind_resp with command status != 0;
    * `{:bound, bind_resp_pdu}` if `pdu` is a bind_resp with command status == 0;
    * `{:ok, resp}` if `pdu` is not a bind resp;

  Returned pdus are built as a reply to proxy client's (ESME) binds/submits and they are expected to be sent to the proxy client.
  """
  @spec handle_mc_resp(
          pdu :: Pdu.t(),
          esme_original_pdu :: Pdu.t(),
          pdu_storage :: pid,
          proxy_mc_bind_pdu :: Pdu.t() | nil
        ) :: {:ok | :bound | :bind_error, Pdu.t()}

  def handle_mc_resp(%Pdu{command_id: cid} = pdu, _, _, proxy_mc_bind_pdu) when cid in @bind_resp_command_ids do
    case Pdu.command_status(pdu) do
      0 ->
        bind_resp = FactoryHelpers.build_response_pdu(proxy_mc_bind_pdu, 0, [Pdu.field(proxy_mc_bind_pdu, :system_id)])
        {:bound, bind_resp}

      err ->
        Logger.warn(fn -> "ProxyESME->MC bind error: #{Pdu.Errors.description(err)}" end)

        bind_resp =
          FactoryHelpers.build_response_pdu(proxy_mc_bind_pdu, :RBINDFAIL, [Pdu.field(proxy_mc_bind_pdu, :system_id)])

        {:bind_error, bind_resp}
    end
  end

  def handle_mc_resp(%Pdu{} = pdu, esme_original_pdu, pdu_storage, _) do
    original_pdu = PduStorage.fetch(pdu_storage, esme_original_pdu.ref)
    resp = Pdu.as_reply_to(pdu, original_pdu)
    PduStorage.delete(pdu_storage, original_pdu.ref)

    {:ok, resp}
  end

  defp bind_account_matches?(bind_pdu, id, pwd) do
    Pdu.field(bind_pdu, :system_id) == id && Pdu.field(bind_pdu, :password) == pwd
  end

  defp allowed_to_proxy?(%{mandatory: %{source_addr: source, destination_addr: dest}}, %{
         senders_whitelist: sw,
         receivers_whitelist: rw
       }) do
    (sw == [] || source in sw) && (rw == [] || dest in rw)
  end

  defp allowed_to_proxy?(_pdu, _config), do: true

  defp start_and_bind_proxy_esme(
         proxy_mc_pid,
         original_bind_pdu,
         %Config{esme_system_id: id, esme_password: pwd} = config
       ) do
    {:ok, proxy_esme_session} = SmppProxy.Proxy.ESME.start_session({proxy_mc_pid, config})

    bind_pdu = original_bind_pdu |> Pdu.set_mandatory_field(:system_id, id) |> Pdu.set_mandatory_field(:password, pwd)
    :ok = SMPPEX.Session.send_pdu(proxy_esme_session, bind_pdu)
    {:ok, proxy_esme_session}
  end
end
