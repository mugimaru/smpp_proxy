defmodule SmppProxy.Proxy.MC.Session do
  @moduledoc """
  `SMPPEX.Session` server that represents connection between proxy client (ESME) and ProxyMC.
  """

  alias SMPPEX.{Pdu, Session}
  alias SmppProxy.Proxy.MC.Impl

  use Session

  defstruct config: nil, mc_bind_pdu: nil, esme: nil, pdu_storage: nil, rate_limiter: nil, bind_state: :unbound

  @type bind_state :: :bound | :unbound

  @type state :: %{
          config: SmppProxy.Config.t(),
          mc_bind_pdu: Pdu.t(),
          esme: pid,
          pdu_storage: pid,
          rate_limiter: pid | nil,
          bind_state: bind_state()
        }

  @impl true
  def init(_socket, _transport, %{config: %SmppProxy.Config{} = config, rate_limiter: rate_limiter}) do
    {:ok, storage} = SmppProxy.Proxy.PduStorage.start_link()

    {:ok,
     struct(
       __MODULE__,
       config: config,
       rate_limiter: rate_limiter,
       pdu_storage: storage
     )}
  end

  @impl true
  def handle_unparsed_pdu(raw_pdu, error, state) do
    Logger.warn(fn -> "PDU parse error #{inspect(error)}; pdu: #{inspect(raw_pdu)}" end)
    {:ok, [SmppProxy.FactoryHelpers.build_response_pdu(raw_pdu, :RSYSERR)], state}
  end

  @impl true
  def handle_pdu(pdu, %{bind_state: :unbound} = state) do
    log_pdu(pdu, :in)

    case Impl.handle_bind_request(self(), pdu, state.config) do
      {:ok, proxy_esme_session} ->
        {:ok, %{state | esme: proxy_esme_session, mc_bind_pdu: pdu}}

      {:error, %Pdu{} = resp} ->
        log_pdu(resp, :out)
        {:ok, [resp], state}
    end
  end

  @impl true
  def handle_pdu(pdu, %{bind_state: :bound} = state) do
    log_pdu(pdu, :in)

    case Impl.proxy_pdu(pdu, state.pdu_storage, state.esme, state.rate_limiter, state.config) do
      {:ok, :proxied} ->
        {:ok, state}

      {:error, %Pdu{} = resp} ->
        log_pdu(resp, :out)
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
    case Impl.handle_mc_resp(pdu, original_pdu, state.pdu_storage, state.mc_bind_pdu) do
      {:bound, %Pdu{} = bind_resp} ->
        log_pdu(bind_resp, :out)
        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil, bind_state: :bound}}

      {:bind_error, %Pdu{} = bind_resp} ->
        log_pdu(bind_resp, :out)
        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil}}

      {:ok, %Pdu{} = resp} ->
        log_pdu(resp, :out)
        {:reply, :ok, [resp], state}
    end
  end

  defp log_pdu(pdu, direction) do
    Logger.debug(fn ->
      prefix = if direction == :in, do: "ESME->ProxyMC ", else: "ESME<-ProxyMC "
      "  " <> prefix <> SmppProxy.PduPrinter.format(pdu)
    end)

    pdu
  end
end
