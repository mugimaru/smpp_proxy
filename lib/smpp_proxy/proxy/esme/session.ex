defmodule SmppProxy.Proxy.ESME.Session do
  @moduledoc """
  `SMPPEX.Session` server that serves connection beetween proxy ESME and MC.
  """

  use SMPPEX.Session
  alias SmppProxy.Proxy.ESME.Impl

  defstruct config: nil, mc_session: nil, pdu_storage: nil

  @type state :: %{
          config: SmppProxy.Config.t(),
          mc_session: pid,
          pdu_storage: pid
        }

  @spec start_link({mc_session :: pid, config :: SmppProxy.Config.t()}) :: {:ok, pid}
  def start_link({mc_session, %SmppProxy.Config{} = config}) do
    args = struct(__MODULE__, mc_session: mc_session, config: config)
    SMPPEX.ESME.start_link(config.esme_host, config.esme_port, {__MODULE__, args})
  end

  @impl true
  def init(_socket, _transport, args) do
    {:ok, storage} = SmppProxy.Proxy.PduStorage.start_link()
    {:ok, %{args | pdu_storage: storage}}
  end

  @impl true
  def handle_unparsed_pdu(raw_pdu, _error, state) do
    {:ok, [SmppProxy.FactoryHelpers.build_response_pdu(raw_pdu, :RSYSERR)], state}
  end

  @impl true
  def handle_pdu(pdu, state) do
    case Impl.handle_pdu_from_mc(pdu, state) do
      {:ok, :proxied} ->
        {:ok, state}

      {:error, %SMPPEX.Pdu{} = resp_pdu} ->
        {:ok, [resp_pdu], state}
    end
  end

  @impl true
  def handle_resp(pdu, original_pdu, %{mc_session: mc} = state) do
    :ok = Impl.handle_resp_from_mc(pdu, original_pdu, mc)
    {:ok, state}
  end

  @impl true
  def terminate(:bound, {err, _} = reason, _mc_session) when err in [:socket_closed, :socket_error] do
    Logger.info("Terminating ESME.Session(#{inspect(self())}); reason #{inspect(reason)};")
    :stop
  end

  def terminate(reason, _lost_pdus, %{bind_state: :bound, mc_session: mc_session}) do
    Logger.info("Terminating ESME.Session(#{inspect(self())}); reason #{inspect(reason)}; Attempting to unbind...")
    :ok = SMPPEX.Session.send_pdu(mc_session, SMPPEX.Pdu.Factory.unbind())
    # we won't wait for unbind_resp, so we are giving mc a constant time to handle our request
    :timer.sleep(100)

    :stop
  end

  def terminate(reason, _lost_pdus, _state) do
    Logger.info("Terminating ESME.Session(#{inspect(self())}); reason #{inspect(reason)};")
    :stop
  end

  @impl true
  def handle_call({:esme_resp, pdu, esme_original_pdu}, _from, state) do
    {:ok, resp} = Impl.handle_resp_from_esme(pdu, esme_original_pdu, state.pdu_storage)
    {:reply, :ok, [resp], state}
  end
end
