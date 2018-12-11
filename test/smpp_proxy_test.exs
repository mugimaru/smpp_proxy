defmodule SmppProxyTest do
  use ExUnit.Case, async: false
  doctest SmppProxy
  doctest SmppProxy.Proxy.PduStorage

  alias SMPPEX.ESME.Sync
  alias SMPPEX.Pdu
  alias SMPPEX.Pdu.Factory, as: PduFactory

  @mc_port (System.get_env("SMPP_PROXY_MC_PORT") || "5051") |> String.to_integer()
  @proxy_mc_port (System.get_env("SMPP_PROXY_ESME_PORT") || "5050") |> String.to_integer()
  @host "localhost"

  @from "from"
  @to "to"
  @text "text"

  @config SmppProxy.Config.new(%{
            mc_port: @proxy_mc_port,
            esme_port: @mc_port,
            esme_host: @host,
            esme_password: "pwd2",
            esme_system_id: "panda",
            mc_password: "pwd",
            mc_system_id: "panda",
            senders_whitelist: [],
            receivers_whitelist: []
          })

  defp with_proxy_up(fun), do: with_proxy_up(@config, fun)

  defp with_proxy_up(config, fun) do
    with_proxy_up(config, %{system_id: config.esme_system_id, password: config.esme_password}, fun)
  end

  defp with_proxy_up(config, mc_credentials, fun) do
    {:ok, mc} = FakeMC.start(config.esme_port, mc_credentials)
    {:ok, proxy} = SmppProxy.Proxy.start_link(config)
    {:ok, esme} = Sync.start_link(@host, config.mc_port)

    try do
      fun.(%{mc: mc, proxy: proxy, esme: esme})
    after
      :ok = GenServer.stop(proxy)
      :ok = SMPPEX.MC.stop(mc)
    end
  end

  test "replies with an error unless proxy esme is in bound state" do
    with_proxy_up(fn %{esme: esme} ->
      {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
      assert resp.command_status == Pdu.Errors.code_by_name(:RBINDFAIL)
    end)
  end

  test "proxies submit_sm and its resp after bind" do
    with_proxy_up(fn %{esme: esme} ->
      {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
      assert bind_resp.command_status == 0
      {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
      assert resp.command_status == 0
    end)
  end

  test "proxy responds with correct sequence numbers" do
    with_proxy_up(fn %{esme: esme} ->
      # issue submit_sm to ensure that ESME->PROXY and PROXY->MC sequences are different
      {:ok, _} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))

      {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
      assert bind_resp.command_status == 0
      {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
      assert resp.command_status == 0
    end)
  end

  test "proxies delivery report" do
    with_proxy_up(fn %{esme: esme} ->
      {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
      assert bind_resp.command_status == 0
      submit_sm = PduFactory.submit_sm(@from, @to, @text, 1)
      {:ok, resp} = Sync.request(esme, submit_sm)
      assert resp.command_status == 0

      [pdu: %Pdu{} = dr] = SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
      assert Pdu.command_name(dr) == :deliver_sm
      assert Pdu.field(dr, :receipted_message_id) == Pdu.field(resp, :message_id)
    end)
  end

  test "proxies mc deliveries" do
    with_proxy_up(fn %{esme: esme} ->
      {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
      assert bind_resp.command_status == 0

      assert [{_, mc_session}] = FakeMC.all_session_pids(@mc_port)

      deliver_sm = PduFactory.deliver_sm("from", "to", "msg")
      :ok = FakeMC.send_pdu(mc_session, deliver_sm)
      [pdu: %Pdu{} = received_pdu] = SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
      assert Pdu.field(received_pdu, :short_message) == Pdu.field(deliver_sm, :short_message)
    end)
  end

  test "responds with bind error on bind with invalid credentials" do
    with_proxy_up(fn %{esme: esme} ->
      {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, "wrong"))
      assert bind_resp.command_status == SMPPEX.Pdu.Errors.code_by_name(:RBINDFAIL)
    end)
  end

  test "responds with bind error if proxy esme bind fails" do
    with_proxy_up(@config, %{system_id: "foo", password: "bar"}, fn %{esme: esme} ->
      {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
      assert bind_resp.command_status == SMPPEX.Pdu.Errors.code_by_name(:RBINDFAIL)
    end)
  end

  describe "senders whitelist" do
    test "proxies submits with source_addr from whitelist" do
      with_proxy_up(%{@config | senders_whitelist: [@from]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0
        {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
        assert resp.command_status == 0
      end)
    end

    test "returns an error for submits with non-whitelisted source addr" do
      with_proxy_up(%{@config | senders_whitelist: ["1"]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0
        {:ok, resp} = Sync.request(esme, PduFactory.submit_sm("unallowed", @to, @text))
        assert resp.command_status == SMPPEX.Pdu.Errors.code_by_name(:RINVSRCADR)
      end)
    end

    test "does not proxy delivers with non-whitelisted dest addr" do
      with_proxy_up(%{@config | senders_whitelist: [@from]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0

        assert [{_, mc_session}] = FakeMC.all_session_pids(@mc_port)

        deliver_sm = PduFactory.deliver_sm(@to, "unallowed", @text)
        :ok = FakeMC.send_pdu(mc_session, deliver_sm)
        assert :timeout == SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
      end)
    end

    test "proxies delivers with whitelisted dest addr" do
      with_proxy_up(%{@config | senders_whitelist: [@from]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0

        assert [{_, mc_session}] = FakeMC.all_session_pids(@mc_port)

        deliver_sm = PduFactory.deliver_sm(@to, @from, @text)
        :ok = FakeMC.send_pdu(mc_session, deliver_sm)
        [pdu: %Pdu{} = received_pdu] = SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
        assert Pdu.field(received_pdu, :short_message) == Pdu.field(deliver_sm, :short_message)
      end)
    end
  end

  describe "source/dest addr whitelists" do
    test "proxies submits with dest_addr from whitelist" do
      with_proxy_up(%{@config | receivers_whitelist: [@to]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0
        {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, @to, @text))
        assert resp.command_status == 0
      end)
    end

    test "returns an error for submits with non-whitelisted dest addr" do
      with_proxy_up(%{@config | receivers_whitelist: [@to]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0
        {:ok, resp} = Sync.request(esme, PduFactory.submit_sm(@from, "unallowed", @text))
        assert resp.command_status == SMPPEX.Pdu.Errors.code_by_name(:RINVSRCADR)
      end)
    end

    test "does not proxy delivers with non-whitelisted dest addr" do
      with_proxy_up(%{@config | receivers_whitelist: [@to]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0

        assert [{_, mc_session}] = FakeMC.all_session_pids(@mc_port)

        deliver_sm = PduFactory.deliver_sm("unallowed", @from, @text)
        :ok = FakeMC.send_pdu(mc_session, deliver_sm)
        assert :timeout == SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
      end)
    end

    test "proxies delivers with whitelisted dest addr" do
      with_proxy_up(%{@config | receivers_whitelist: [@to]}, fn %{esme: esme} ->
        {:ok, bind_resp} = Sync.request(esme, PduFactory.bind_transceiver(@config.mc_system_id, @config.mc_password))
        assert bind_resp.command_status == 0

        assert [{_, mc_session}] = FakeMC.all_session_pids(@mc_port)

        deliver_sm = PduFactory.deliver_sm(@to, @from, @text)
        :ok = FakeMC.send_pdu(mc_session, deliver_sm)
        [pdu: %Pdu{} = received_pdu] = SMPPEX.ESME.Sync.wait_for_pdus(esme, 1000)
        assert Pdu.field(received_pdu, :short_message) == Pdu.field(deliver_sm, :short_message)
      end)
    end
  end
end
