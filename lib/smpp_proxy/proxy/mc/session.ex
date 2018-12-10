defmodule SmppProxy.Proxy.MC.Session do
  alias SMPPEX.{Pdu, Session}
  alias SmppProxy.Proxy.MC.Impl

  use Session

  defstruct config: nil, mc_bind_pdu: nil, esme: nil, pdu_storage: nil, bind_state: :unbound

  @type bind_state :: :bound | :unbound

  @type state :: %{
    config: SmppProxy.Config.t(),
    mc_bind_pdu: Pdu.t(),
    esme: pid,
    pdu_storage: pid,
    bind_state: bind_state()
  }

  @impl true
  def init(_socket, _transport, %SmppProxy.Config{} = args) do
    {:ok, storage} = SmppProxy.Proxy.PduStorage.start_link()
    {:ok, struct(__MODULE__, config: args, pdu_storage: storage)}
  end

  @impl true
  def handle_unparsed_pdu(raw_pdu, _error, state) do
    {:ok, [SmppProxy.FactoryHelpers.build_response_pdu(raw_pdu, :RSYSERR)], state}
  end

  @impl true
  def handle_pdu(pdu, %{bind_state: :unbound} = state) do
    Logger.debug(fn -> "ProxyMC: handling bind request" end)

    case Impl.handle_bind_request(pdu, state.config) do
      {:ok, proxy_esme_session} ->
        {:ok, %{state | esme: proxy_esme_session, mc_bind_pdu: pdu}}

      {:error, %Pdu{} = resp} ->
        {:ok, [resp], state}
    end
  end

  @impl true
  def handle_pdu(pdu, %{bind_state: :bound} = state) do
    case Impl.proxy_pdu(pdu, state.pdu_storage, state.esme, state.config) do
      {:ok, :proxied} ->
        {:ok, state}

      {:error, %Pdu{} = resp} ->
        {:ok, [resp], state}
    end
  end

  @impl true
  def handle_socket_closed(state) do
    Logger.info("MC.Session(#{inspect(self())}); Socket closed")
    {:normal, state}
  end

  @impl true
  def terminate(reason, _lost_pdus, _st) do
    Logger.info("Terminating MC.Session(#{inspect(self())}); reason #{inspect(reason)}")
    :stop
  end

  @impl true
  def handle_call({:handle_mc_resp, pdu, original_pdu}, _from, state) do
    if SMPPEX.Pdu.command_name(pdu) in [:bind_transceiver_resp, :bind_transmitter_resp, :bind_receiver_resp] do
      case Impl.handle_mc_bind_resp(pdu, state.mc_bind_pdu) do
        {:ok, bind_resp} ->
          Logger.debug(fn -> "ProxyMC(#{state.bind_state}): ProxyESME bound" end)
          {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil, bind_state: :bound}}

        {:error, bind_resp} ->
          Logger.debug(fn ->
            error_desc = SMPPEX.Pdu.command_status(pdu) |> SMPPEX.Pdu.Errors.description()
            "ProxyMC(#{state.bind_state}): ProxyESME bind error #{error_desc}"
          end)

          {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil}}
      end
    else
      {:ok, resp} = Impl.handle_mc_resp(pdu, original_pdu, state.pdu_storage)
      {:reply, :ok, [resp], state}
    end
  end
end
