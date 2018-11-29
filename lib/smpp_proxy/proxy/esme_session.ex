defmodule SmppProxy.Proxy.ESMESession do
  alias SMPPEX.Session
  alias SmppProxy.Proxy.PduStorage
  use Session

  defstruct config: nil, mc_session: nil, pdu_storage: nil

  def start_link({mc_session, %SmppProxy.Config{} = config}) do
    args = struct(__MODULE__, mc_session: mc_session, config: config)
    SMPPEX.ESME.start_link(config.esme_host, config.esme_port, {__MODULE__, args})
  end

  def init(_socket, _transport, args) do
    {:ok, storage} = PduStorage.start_link()
    {:ok, %{args | pdu_storage: storage}}
  end

  def handle_pdu(pdu, state) do
    PduStorage.store(state.pdu_storage, pdu)
    Session.send_pdu(state.mc_session, pdu)
    {:ok, state}
  end

  def handle_unparsed_pdu(raw_pdu, state) do
    PduStorage.store(state.pdu_storage, raw_pdu)
    Session.send_pdu(state.mc_session, raw_pdu)
    {:ok, state}
  end

  def handle_resp(pdu, original_pdu, state) do
    if SMPPEX.Pdu.command_name(pdu) in [:bind_transceiver_resp, :bind_transmitter_resp, :bind_receiver_resp] do
      :ok = Session.call(state.mc_session, {:esme_bind_resp, pdu})
    else
      :ok = Session.call(state.mc_session, {:proxy_resp, pdu, original_pdu})
    end

    {:ok, state}
  end

  def handle_call({:proxy_resp, pdu, mc_original_pdu}, _from, state) do
    original_pdu = PduStorage.fetch(state.pdu_storage, mc_original_pdu.ref)
    resp = SMPPEX.Pdu.as_reply_to(pdu, original_pdu)
    PduStorage.delete(state.pdu_storage, original_pdu.ref)

    {:reply, :ok, [resp], state}
  end
end
