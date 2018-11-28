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
end
