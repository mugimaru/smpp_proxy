defmodule SmppProxy.Proxy.MCSession do
  alias SMPPEX.{Pdu, Session}
  alias Pdu.Factory, as: PduFactory
  alias Pdu.Errors, as: PduErrors
  alias SmppProxy.{Config, Proxy.PduStorage}

  import SmppProxy.FactoryHelpers, only: [build_response_pdu: 2, build_response_pdu: 3]

  use Session

  defstruct config: nil, mc_bind_pdu: nil, esme: nil, pdu_storage: nil, esme_bound: false

  def init(_socket, _transport, %SmppProxy.Config{} = args) do
    {:ok, storage} = PduStorage.start_link()
    {:ok, struct(__MODULE__, config: args, pdu_storage: storage)}
  end

  def handle_pdu(pdu, %{esme_bound: false} = state) do
    if Pdu.command_name(pdu) == Config.bind_command_name(state.config) && bind_account_matches?(pdu, state.config) do
      {:ok, esme} = SmppProxy.Proxy.ESMESession.start_link({self(), state.config})

      :ok =
        Session.send_pdu(
          esme,
          apply(PduFactory, Config.bind_command_name(state.config), [
            state.config.esme_system_id,
            state.config.esme_password
          ])
        )

      {:ok, %{state | esme: esme, mc_bind_pdu: pdu}}
    else
      {:ok, resp} = build_response_pdu(pdu, :RBINDFAIL)
      {:ok, [resp], state}
    end
  end

  def handle_pdu(pdu, %{esme_bound: true} = state) do
    if allowed_to_proxy?(pdu, state.config) do
      PduStorage.store(state.pdu_storage, pdu)
      Session.send_pdu(state.esme, pdu)
      {:ok, state}
    else
      case build_response_pdu(pdu, :RINVSRCADR) do
        {:ok, resp} ->
          {:ok, [resp], state}

        {:error, _} ->
          Logger.warn(fn -> "Unable to build response; unknown pdu: #{inspect(pdu)}" end)
          {:ok, state}
      end
    end
  end

  def handle_call({:esme_bind_resp, pdu}, _from, %{mc_bind_pdu: mc_bind_pdu} = state) do
    case Pdu.command_status(pdu) do
      0 ->
        {:ok, bind_resp} = build_response_pdu(mc_bind_pdu, 0, [Pdu.field(mc_bind_pdu, :system_id)])
        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil, esme_bound: true}}

      err ->
        Logger.warn(fn -> "ESME bind error: #{Pdu.Errors.description(err)}" end)
        {:ok, bind_resp} = build_response_pdu(mc_bind_pdu, :RBINDFAIL, [Pdu.field(mc_bind_pdu, :system_id)])

        {:reply, :ok, [bind_resp], %{state | mc_bind_pdu: nil}}
    end
  end

  def handle_call({:proxy_resp, pdu, esme_original_pdu}, _from, state) do
    original_pdu = PduStorage.fetch(state.pdu_storage, esme_original_pdu.ref)
    resp = Pdu.as_reply_to(pdu, original_pdu)
    PduStorage.delete(state.pdu_storage, original_pdu.ref)
    {:reply, :ok, [resp], state}
  end

  defp bind_account_matches?(bind_pdu, %{mc_system_id: id, mc_password: pwd}) do
    Pdu.field(bind_pdu, :system_id) == id && Pdu.field(bind_pdu, :password) == pwd
  end

  defp allowed_to_proxy?(%{mandatory: %{source_addr: source, destination_addr: dest}}, config) do
    SmppProxy.Proxy.allowed_to_proxy?(config, sender: source, receiver: dest)
  end

  defp allowed_to_proxy?(_pdu, _config), do: true
end
