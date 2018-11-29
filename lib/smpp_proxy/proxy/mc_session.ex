defmodule SmppProxy.Proxy.MCSession do
  alias SMPPEX.{Pdu, Session}
  alias Pdu.Factory, as: PduFactory
  alias Pdu.Errors, as: PduErrors
  alias SmppProxy.Config
  alias SmppProxy.Proxy.PduStorage

  use Session

  defstruct config: nil, mc_bind_pdu: nil, esme: nil, pdu_storage: nil, esme_bound: false

  def init(_socket, _transport, %SmppProxy.Config{} = args) do
    {:ok, storage} = PduStorage.start_link()
    {:ok, struct(__MODULE__, config: args, pdu_storage: storage)}
  end

  def handle_pdu(pdu, %{esme_bound: false} = state) do
    if Pdu.command_name(pdu) == Config.bind_command_name(state.config) do
      {:ok, esme} = SmppProxy.Proxy.ESMESession.start_link({self(), state.config})
      :ok = Session.send_pdu(esme, PduFactory.bind_transceiver(state.config.esme_system_id, state.config.esme_password))

      {:ok, %{state | esme: esme, mc_bind_pdu: pdu}}
    else
      resp = PduErrors.code_by_name(:RINVBNDSTS) |> PduFactory.submit_sm_resp() |> Pdu.as_reply_to(pdu)
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
        resp = PduErrors.code_by_name(:RINVCMDID) |> PduFactory.submit_sm_resp() |> Pdu.as_reply_to(pdu)
        {:ok, [resp], state}
    end
  end

  def handle_call({:esme_bind_resp, pdu}, _from, %{mc_bind_pdu: mc_bind_pdu} = state) do
    case Pdu.command_status(pdu) do
      0 ->
        bind_resp =
          PduFactory
          |> apply(Config.bind_resp_command_name(state.config), [0, state.config.mc_system_id])
          |> Pdu.as_reply_to(mc_bind_pdu)
        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil, esme_bound: true}}

      err ->
        Logger.warn(fn -> "ESME bind error: #{Pdu.Errors.description(err)}" end)
        bind_resp =
          PduFactory
          |> apply(Config.bind_resp_command_name(state.config), [PduErrors.code_by_name(:RBINDFAIL), state.config.mc_system_id])
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
