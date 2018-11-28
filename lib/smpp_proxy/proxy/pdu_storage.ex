defmodule SmppProxy.Proxy.PduStorage do
  use Agent

  def start_link() do
    Agent.start_link(fn -> %{} end)
  end

  def store(pid, pdu) do
    Agent.update(pid, fn map ->
      Map.put(map, pdu.ref, pdu)
    end)
  end

  def fetch(pid, ref) do
    Agent.get(pid, fn map ->
      Map.get(map, ref)
    end)
  end

  def delete(pid, ref) do
    Agent.update(pid, fn map ->
      Map.delete(map, ref)
    end)
  end
end
