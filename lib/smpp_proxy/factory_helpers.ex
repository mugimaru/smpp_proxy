defmodule SmppProxy.FactoryHelpers do
  alias SMPPEX.Pdu

  @responses %{
    bind_receiver: :bind_receiver_resp,
    bind_transceiver: :bind_transceiver_resp,
    bind_transmitter: :bind_transmitter_resp,
    submit_sm: :submit_sm_resp,
    deliver_sm: :deliver_sm_resp,
    cancel_sm: :cancel_sm_resp,
    enquire_link: :enquire_link_resp,
    query_sm: :query_sm_resp,
    unbind: :unbind_resp,
    replace_sm: :replace_sm_resp,
    submit_multi: :submit_multi_resp,
    data_sm: :data_sm_resp
  }

  def build_response_pdu(pdu, code_or_name), do: build_response_pdu(pdu, code_or_name, [])

  def build_response_pdu(pdu, error_name, args) when is_atom(error_name) do
    error_code = Pdu.Errors.code_by_name(error_name)
    build_response_pdu(pdu, error_code, args)
  end

  def build_response_pdu(pdu, status_code, args) do
    apply(Pdu.Factory, response_command_name(pdu), [status_code | args]) |> Pdu.as_reply_to(pdu)
  end

  defp response_command_name(pdu) do
    Map.get(@responses, Pdu.command_name(pdu), :generic_nack)
  end
end
