defmodule FakeMC do
  use SMPPEX.Session

  require Logger

  alias SMPPEX.Pdu
  alias SMPPEX.Pdu.Factory, as: PduFactory

  @name_prefix "fake_mc_"
  def all_session_names(port) do
    Process.registered() |> Enum.filter(fn atom -> String.contains?(to_string(atom), "#{@name_prefix}#{port}") end)
  end

  def all_session_pids(port) do
    port |> all_session_names() |> Enum.map(fn name -> {name, Process.whereis(name)} end)
  end

  def start(port, config \\ %{}) do
    SMPPEX.MC.start({__MODULE__, Map.put(config, :port, port)}, transport_opts: [port: port])
  end

  def init(_socket, _transport, args) do
    register_process_name(args[:port], self())
    {:ok, Map.put(args, :id, 0)}
  end

  def handle_pdu(pdu, %{id: last_id} = state) do
    case Pdu.command_name(pdu) do
      :submit_sm ->
        resp = reply(PduFactory.submit_sm_resp(0, to_string(last_id)), pdu)

        pdu_to_send =
          if Pdu.field(pdu, :registered_delivery) == 1 do
            [resp, PduFactory.delivery_report_for_submit_sm(to_string(last_id), pdu)]
          else
            [resp]
          end

        {:ok, pdu_to_send, %{state | id: last_id + 1}}

      :bind_transceiver ->
        resp =
          if bind_account_matches?(pdu, state) do
            reply(PduFactory.bind_transceiver_resp(0), pdu)
          else
            reply(PduFactory.bind_transceiver_resp(SMPPEX.Pdu.Errors.code_by_name(:RBINDFAIL)), pdu)
          end

        {:ok, [resp], state}

      _ ->
        {:ok, last_id}
    end
  end

  def send_pdu(pid, pdu) do
    SMPPEX.Session.call(pid, {:send_pdu, pdu})
  end

  def handle_call({:send_pdu, pdu}, _, state) do
    {:reply, :ok, [pdu], state}
  end

  defp reply(pdu, reply_to_pdu) do
    Pdu.as_reply_to(pdu, reply_to_pdu)
  end

  defp register_process_name(port, pid) do
    next_id =
      case all_session_names(port) |> List.last() do
        nil ->
          1

        name ->
          id_from_process_name(name, port) + 1
      end

    Process.register(pid, process_name_for(port, next_id))
  end

  defp process_name_for(port, id) do
    "#{@name_prefix}#{port}_#{id}" |> String.to_atom()
  end

  defp id_from_process_name(atom, port) do
    atom |> to_string |> String.replace("#{@name_prefix}#{port}_", "") |> String.to_integer()
  end

  defp bind_account_matches?(bind_pdu, %{system_id: id, password: pwd}) do
    Pdu.field(bind_pdu, :system_id) == id && Pdu.field(bind_pdu, :password) == pwd
  end

  defp bind_account_matches?(_bind_pdu, _), do: true
end
