defmodule SmppProxy.FactoryHelpersTest do
  use ExUnit.Case, async: true
  doctest SmppProxy.FactoryHelpers

  alias SMPPEX.Pdu
  import SmppProxy.FactoryHelpers

  test "supports status names alongside with status codes" do
    error_name = :RINVNUMDESTS
    error_code = Pdu.Errors.code_by_name(error_name)

    by_name = build_response_pdu(Pdu.new({-1, 0, 0}), error_name)
    by_code = build_response_pdu(Pdu.new({-1, 0, 0}), error_code)

    assert Pdu.command_id(by_code) == Pdu.command_id(by_name)
    assert Pdu.command_status(by_code) == Pdu.command_status(by_name)
  end
end
