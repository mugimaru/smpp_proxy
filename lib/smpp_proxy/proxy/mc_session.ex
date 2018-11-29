defmodule SmppProxy.Proxy.MCSession do
  alias SMPPEX.{Pdu, Session}
  alias SmppProxy.Proxy.PduStorage
  use Session

  defstruct config: nil, mc_bind_pdu: nil, esme: nil, pdu_storage: nil, esme_bound: false

  def init(_socket, _transport, args) do
    {:ok, storage} = PduStorage.start_link()
    {:ok, struct(__MODULE__, config: args, pdu_storage: storage)}
  end

  def handle_pdu(pdu, %{esme_bound: false} = state) do
    case Pdu.command_name(pdu) do
      :bind_transceiver ->
        {:ok, esme} = bind_to_esme(state.config)
        {:ok, %{state | esme: esme, mc_bind_pdu: pdu}}

      _ ->
        resp = Pdu.Errors.code_by_name(:RINVBNDSTS) |> Pdu.Factory.submit_sm_resp() |> Pdu.as_reply_to(pdu)
        {:ok, [resp], state}
    end
  end

  def handle_pdu(pdu, %{esme_bound: true} = state) do
    case Pdu.command_name(pdu) do
      :submit_sm ->
        PduStorage.store(state.pdu_storage, pdu)
        Session.send_pdu(state.esme, pdu)
        {:ok, state}

      _ ->
        resp = Pdu.Errors.code_by_name(:RINVCMDID) |> Pdu.Factory.submit_sm_resp() |> Pdu.as_reply_to(pdu)
        {:ok, [resp], state}
    end
  end

  defp bind_to_esme(%{esme_port: esme_port, esme_host: esme_host}) do
    {:ok, esme} = SmppProxy.Proxy.ESMESession.start_link(%{port: esme_port, host: esme_host, mc_session: self()})
    bind = Pdu.Factory.bind_transceiver("system_id", "password")
    :ok = Session.send_pdu(esme, bind)

    {:ok, esme}
  end

  def handle_call({:esme_bind_resp, pdu}, _from, %{mc_bind_pdu: mc_bind_pdu} = state) do
    case Pdu.command_status(pdu) do
      0 ->
        bind_resp = Pdu.Factory.bind_transceiver_resp(0, "system_id") |> Pdu.as_reply_to(mc_bind_pdu)
        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil, esme_bound: true}}

      err ->
        Logger.warn(fn -> "ESME bind error: #{Pdu.Errors.description(err)}" end)

        bind_resp =
          Pdu.Errors.code_by_name(:RBINDFAIL)
          |> Pdu.Factory.bind_transceiver_resp("system_id")
          |> Pdu.as_reply_to(mc_bind_pdu)

        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil}}
    end
  end

  def handle_call({:proxy_resp, pdu, esme_original_pdu}, _from, state) do
    original_pdu = PduStorage.fetch(state.pdu_storage, esme_original_pdu.ref)
    resp = Pdu.as_reply_to(pdu, original_pdu)
    PduStorage.delete(state.pdu_storage, original_pdu.ref)
    {:reply, :ok, [resp], state}
  end
end
