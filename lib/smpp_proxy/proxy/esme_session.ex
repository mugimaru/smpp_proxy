defmodule SmppProxy.Proxy.ESMESession do
  use SMPPEX.Session
  alias SMPPEX.Pdu

  def start_link(%{host: host, port: port} = args) do
    SMPPEX.ESME.start_link(host, port, {__MODULE__, args})
  end

  def handle_resp(pdu, original_pdu, state) do
    case Pdu.command_name(pdu) do
      :bind_transceiver_resp ->
        :ok = SMPPEX.Session.call(state[:mc_session], {:esme_bind_resp, pdu})
        {:ok, state}

      :submit_sm_resp ->
        :ok = SMPPEX.Session.call(state[:mc_session], {:proxy_resp, pdu, original_pdu})
        {:ok, state}
    end
  end
end
