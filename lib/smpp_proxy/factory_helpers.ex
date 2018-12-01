defmodule SmppProxy.FactoryHelpers do
  alias SMPPEX.Pdu

  def build_response_pdu(pdu, code_or_name), do: build_response_pdu(pdu, code_or_name, [])

  def build_response_pdu(pdu, error_name, args) when is_atom(error_name) do
    error_code = Pdu.Errors.code_by_name(error_name)
    build_response_pdu(pdu, error_code, args)
  end

  def build_response_pdu(pdu, status_code, args) do
    with {:ok, command_name} <- response_command_name(pdu) do
      response = apply(Pdu.Factory, command_name, [status_code | args]) |> Pdu.as_reply_to(pdu)
      {:ok, response}
    end
  end

  def response_command_name(pdu) do
    case Pdu.command_name(pdu) do
      :bind_receiver ->
        {:ok, :bind_receiver_resp}

      :bind_transceiver ->
        {:ok, :bind_transceiver_resp}

      :bind_transmitter ->
        {:ok, :bind_transmitter_resp}

      :submit_sm ->
        {:ok, :submit_sm_resp}

      :deliver_sm ->
        {:ok, :deliver_sm_resp}

      :cancel_sm ->
        {:ok, :cancel_sm_resp}

      :enquire_link ->
        {:ok, :enquire_link_resp}

      :query_sm ->
        {:ok, :query_sm_resp}

      :unbind ->
        {:ok, :unbind_resp}

      :replace_sm ->
        {:ok, :replace_sm_resp}

      :submit_multi ->
        {:ok, :submit_multi_resp}

      :data_sm ->
        {:ok, :data_sm_resp}

      _ ->
        {:error, :unknown_command}
    end
  end
end
