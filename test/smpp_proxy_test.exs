defmodule SmppProxyTest do
  use ExUnit.Case, async: false
  doctest SmppProxy

  alias SMPPEX.{Pdu, ESME.Sync}
  alias Pdu.Factory, as: PduFactory

  @mc_port 5051
  @proxy_mc_port 5050
  @host "localhost"

  @from "from"
  @to "to"
  @text "text"

  setup do
    {:ok, mc} = FakeMC.start(@mc_port)
    {:ok, proxy} = SmppProxy.Proxy.start_link(%{mc_port: @proxy_mc_port, esme_port: @mc_port, esme_host: @host})
    {:ok, esme} = Sync.start_link(@host, @proxy_mc_port)

    {:ok, [proxy: proxy, esme: esme, mc: mc]}
  end

  test "replies with an error unless proxy esme is in bound state", %{esme: esme, mc: mc, proxy: proxy} do
    {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
    assert resp.command_status == Pdu.Errors.code_by_name(:RINVBNDSTS)

    :ok = GenServer.stop(proxy)
    :ok = SMPPEX.MC.stop(mc)
  end

  test "proxies submit_sm and its resp after bind", %{esme: esme, proxy: proxy, mc: mc} do
    {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver("systemid", "password"))
    assert bind_resp.command_status == 0
    {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
    assert resp.command_status == 0

    :ok = GenServer.stop(proxy)
    :ok = SMPPEX.MC.stop(mc)
  end

  test "proxy responds with correct sequence numbers", %{esme: esme, proxy: proxy, mc: mc} do
    # issue submit_sm to ensure that ESME->PROXY and PROXY->MC sequences are different
    {:ok, _} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))

    {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver("systemid", "password"))
    assert bind_resp.command_status == 0
    {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
    assert resp.command_status == 0

    :ok = GenServer.stop(proxy)
    :ok = SMPPEX.MC.stop(mc)
  end

  test "proxies delivery report", %{esme: esme, proxy: proxy, mc: mc} do
    {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver("systemid", "password"))
    assert bind_resp.command_status == 0
    submit_sm = PduFactory.submit_sm(@from, @to, @text, 1)
    {:ok, resp} = Sync.request(esme, submit_sm)
    assert resp.command_status == 0

    [pdu: %Pdu{} = dr] = SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
    assert Pdu.command_name(dr) == :deliver_sm
    assert Pdu.field(dr, :receipted_message_id) == Pdu.field(resp, :message_id)

    :ok = GenServer.stop(proxy)
    :ok = SMPPEX.MC.stop(mc)
  end

  test "proxies mc deliveries", %{esme: esme, proxy: proxy, mc: mc} do
    {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver("systemid", "password"))
    assert bind_resp.command_status == 0

    assert [{_, mc_session}] = FakeMC.all_session_pids(@mc_port)

    deliver_sm = PduFactory.deliver_sm("from", "to", "msg")
    :ok = FakeMC.send_pdu(mc_session, deliver_sm)
    [pdu: %Pdu{} = received_pdu] = SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
    assert Pdu.field(received_pdu, :short_message) == Pdu.field(deliver_sm, :short_message)

    :ok = GenServer.stop(proxy)
    :ok = SMPPEX.MC.stop(mc)
  end
end
