defmodule SmppProxy.FactoryHelpers do
  @moduledoc """
  Wrappers for `SMPPEX.Pdu.Factory`.
  """

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
  @generic_nack SMPPEX.Protocol.CommandNames.id_by_name(:generic_nack) |> elem(1)

  @doc """
  Build response for given pdu. Returns :generic_nack for unknown/unparsed pdus.

  ## Examples

  returns submit_sm_resp pdu for submit_sm:

      iex> resp = SMPPEX.Pdu.Factory.submit_sm("from", "to", "text") |> SmppProxy.FactoryHelpers.build_response_pdu(2)
      iex> assert SMPPEX.Pdu.command_name(resp)
      :submit_sm_resp
      iex> assert SMPPEX.Pdu.command_status(resp)
      2

  returns generic_nack pdu for unknown pdus:

      iex> resp = SMPPEX.Pdu.new({-1, 0, 0}) |> SmppProxy.FactoryHelpers.build_response_pdu(2)
      iex> SMPPEX.Pdu.command_name(resp)
      :generic_nack
      iex> assert SMPPEX.Pdu.command_status(resp)
      2
  """
  @spec build_response_pdu(SMPPEX.Pdu.t() | SMPPEX.RawPdu.t(), any()) :: SMPPEX.Pdu.t()
  @spec build_response_pdu(SMPPEX.Pdu.t() | SMPPEX.RawPdu.t(), any(), [any()]) :: SMPPEX.Pdu.t()

  def build_response_pdu(pdu, code_or_name), do: build_response_pdu(pdu, code_or_name, [])

  def build_response_pdu(pdu, error_name, args) when is_atom(error_name) do
    error_code = Pdu.Errors.code_by_name(error_name)
    build_response_pdu(pdu, error_code, args)
  end

  def build_response_pdu(pdu, status_code, args) do
    case Map.get(@responses, Pdu.command_name(pdu)) do
      nil ->
        Pdu.new({@generic_nack, status_code, 0})

      command_name ->
        apply(Pdu.Factory, command_name, [status_code | args])
    end
    |> Pdu.as_reply_to(pdu)
  end
end
