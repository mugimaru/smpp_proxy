defmodule SmppProxy.FactoryHelpersTest do
  use ExUnit.Case, async: true

  alias SMPPEX.Pdu
  import SmppProxy.FactoryHelpers

  test "returns submit_sm_resp pdu for submit_sm" do
    resp = Pdu.Factory.submit_sm("from", "to", "text") |> build_response_pdu(2)
    assert Pdu.command_name(resp) == :submit_sm_resp
    assert Pdu.command_status(resp) == 2
  end

  test "returns generic_nack pdu for unknown pdus" do
    resp = Pdu.new({-1, 0, 0}) |> build_response_pdu(2)
    assert Pdu.command_name(resp) == :generic_nack
    assert Pdu.command_status(resp) == 2
  end

  test "supports status names alongside with status codes" do
    error_name = :RINVNUMDESTS
    error_code = Pdu.Errors.code_by_name(error_name)

    by_name = build_response_pdu(Pdu.new({-1, 0, 0}), error_name)
    by_code = build_response_pdu(Pdu.new({-1, 0, 0}), error_code)

    assert Pdu.command_id(by_code) == Pdu.command_id(by_name)
    assert Pdu.command_status(by_code) == Pdu.command_status(by_name)
  end
end
