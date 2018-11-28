defmodule FakeMC do
  use SMPPEX.Session

  require Logger

  alias SMPPEX.Pdu
  alias SMPPEX.Pdu.Factory, as: PduFactory

  def start(port) do
    SMPPEX.MC.start({__MODULE__, []}, transport_opts: [port: port])
  end

  def init(socket, transport, []) do
    {:ok, %{transport: transport, socket: socket, id: 0}}
  end

  def handle_pdu(pdu, %{id: last_id} = state) do
    case Pdu.command_name(pdu) do
      :submit_sm ->
        {:ok, [reply(PduFactory.submit_sm_resp(0, to_string(last_id)), pdu)], %{state | id: last_id + 1}}

      :bind_transmitter ->
        {:ok, [reply(PduFactory.bind_transmitter_resp(0), pdu)], state}

      :bind_transceiver ->
        {:ok, [reply(PduFactory.bind_transceiver_resp(0), pdu)], state}

      _ ->
        {:ok, last_id}
    end
  end

  def send_pdu(mc, pdu) do
    GenServer.call(mc, {:send_pdu, pdu})
  end

  def handle_call({:send_pdu, pdu}, _, %{transport: transport} = state) do
    {:reply, SMPPEX.Session.send_pdu(transport, pdu), state}
  end

  defp reply(pdu, reply_to_pdu) do
    Pdu.as_reply_to(pdu, reply_to_pdu)
  end
end
