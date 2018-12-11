defmodule SmppProxy.Proxy.PduStorage do
  @moduledoc """
  Stores `SMPPEX.Pdu` in `Agent` state by `pdu.ref`.

  ### Examples

      iex> pdu = SMPPEX.Pdu.new({1, 2, 3})
      iex> {:ok, pid} = SmppProxy.Proxy.PduStorage.start_link()
      iex> :ok = SmppProxy.Proxy.PduStorage.store(pid, pdu)
      iex> ^pdu = SmppProxy.Proxy.PduStorage.fetch(pid, pdu.ref)
      iex> :ok = SmppProxy.Proxy.PduStorage.delete(pid, pdu.ref)
      iex> SmppProxy.Proxy.PduStorage.fetch(pid, pdu.ref)
      nil
  """

  use Agent
  alias SMPPEX.Pdu

  @spec start_link :: {:ok, pid}
  def start_link do
    Agent.start_link(fn -> %{} end)
  end

  @spec store(pid, Pdu.t()) :: :ok
  def store(pid, %Pdu{} = pdu) do
    Agent.update(pid, fn map ->
      Map.put(map, pdu.ref, pdu)
    end)
  end

  @spec fetch(pid, ref :: reference) :: nil | Pdu.t()
  def fetch(pid, ref) do
    Agent.get(pid, fn map ->
      Map.get(map, ref)
    end)
  end

  @spec delete(pid, ref :: reference) :: :ok
  def delete(pid, ref) do
    Agent.update(pid, fn map ->
      Map.delete(map, ref)
    end)
  end
end
