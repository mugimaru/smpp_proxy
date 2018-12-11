defmodule SmppProxy.PduPrinter do
  @moduledoc """
  Formats `SMPPEX.Pdu` into single line string for printing/logging.

  ## Examples

      iex> SmppProxy.PduPrinter.format SMPPEX.Pdu.Factory.submit_sm("from", "to", "text")
      "submit_sm(from, to)"

      iex> SmppProxy.PduPrinter.format SMPPEX.Pdu.Factory.deliver_sm("source", "dest", "text")
      "deliver_sm(source, dest)"

      iex> SmppProxy.PduPrinter.format SMPPEX.Pdu.Factory.submit_sm_resp(0)
      "submit_sm_resp(0)"

      iex> SmppProxy.PduPrinter.format SMPPEX.Pdu.Factory.submit_sm_resp(3)
      "submit_sm_resp(Invalid Command ID)"

      iex> SmppProxy.PduPrinter.format SMPPEX.Pdu.Factory.bind_transmitter("sid", "pwd")
      "bind_transmitter(sid, pwd)"
  """
  alias SMPPEX.Pdu

  @spec format(pdu :: Pdu.t()) :: String.t()
  def format(%Pdu{} = pdu) do
    command_name = Pdu.command_name(pdu) |> to_string
    command_status = Pdu.command_status(pdu)
    command_result = if command_status == 0, do: "0", else: SMPPEX.Pdu.Errors.description(command_status)

    source_addr = Pdu.mandatory_field(pdu, :source_addr)
    dest_addr = Pdu.mandatory_field(pdu, :destination_addr)

    cond do
      source_addr && dest_addr ->
        "#{command_name}(#{source_addr}, #{dest_addr})"

      String.contains?(command_name, "_resp") ->
        "#{command_name}(#{command_result})"

      String.contains?(command_name, "bind_") ->
        "#{command_name}(#{Pdu.mandatory_field(pdu, :system_id)}, #{Pdu.mandatory_field(pdu, :password)})"

      true ->
        "#{command_name}(#{command_result})"
    end
  end
end
