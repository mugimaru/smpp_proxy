defmodule SmppProxy.Proxy.MC.Session do
  alias SMPPEX.{Pdu, Session}
  alias SmppProxy.Proxy.MC.Impl

  use Session

  defstruct config: nil, mc_bind_pdu: nil, esme: nil, pdu_storage: nil, esme_bound: false

  @impl true
  def init(_socket, _transport, %SmppProxy.Config{} = args) do
    {:ok, storage} = SmppProxy.Proxy.PduStorage.start_link()
    {:ok, struct(__MODULE__, config: args, pdu_storage: storage)}
  end

  @impl true
  def handle_unparsed_pdu(raw_pdu, _error, state) do
    case SmppProxy.FactoryHelpers.build_response_pdu(raw_pdu, :RSYSERR) do
      {:ok, pdu} ->
        {:ok, [pdu], state}

      _ ->
        Logger.warn("MC.Session has received unknown PDU #{inspect(raw_pdu)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_pdu(pdu, %{esme_bound: false} = state) do
    case Impl.handle_pdu_from_esme_in_unbound_state(pdu, state.config) do
      {:ok, proxy_esme_session} ->
        {:ok, %{state | esme: proxy_esme_session, mc_bind_pdu: pdu}}

      {:error, %Pdu{} = resp} ->
        {:ok, [resp], state}

      {:error, _} ->
        {:ok, state}
    end
  end

  @impl true
  def handle_pdu(pdu, %{esme_bound: true} = state) do
    case Impl.handle_pdu_from_esme_in_bound_state(pdu, state.pdu_storage, state.esme, state.config) do
      {:ok, :proxied} ->
        {:ok, state}

      {:error, %Pdu{} = resp} ->
        {:ok, [resp], state}

      {:error, _} ->
        {:ok, state}
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
          {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil, esme_bound: true}}

        {:error, bind_resp} ->
          {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil}}
      end
    else
      {:ok, resp} = Impl.handle_mc_resp(pdu, original_pdu, state.pdu_storage)
      {:reply, :ok, [resp], state}
    end
  end
end
