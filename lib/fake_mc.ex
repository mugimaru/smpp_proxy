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
        resp = reply(PduFactory.submit_sm_resp(0, to_string(last_id)), pdu)
        pdu_to_send =
          if Pdu.field(pdu, :registered_delivery) == 1 do
            [resp, PduFactory.delivery_report_for_submit_sm(to_string(last_id), pdu)]
          else
            [resp]
          end

        {:ok, pdu_to_send, %{state | id: last_id + 1}}

      :bind_transmitter ->
        {:ok, [reply(PduFactory.bind_transmitter_resp(0), pdu)], state}

      :bind_transceiver ->
        {:ok, [reply(PduFactory.bind_transceiver_resp(0), pdu)], state}

      _ ->
        {:ok, last_id}
    end
  end

  defp reply(pdu, reply_to_pdu) do
    Pdu.as_reply_to(pdu, reply_to_pdu)
  end
end
