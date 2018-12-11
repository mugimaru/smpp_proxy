defmodule SmppProxy.RateLimiter do
  @moduledoc """
  Primive rate limiter.

      {:ok, pid} = SmppProxy.RateLimiter.start_link(10, :second) # up to 10 requests per second
      SmppProxy.RateLimiter.take(pid)
      true
  """

  use GenServer

  defstruct n: nil, interval: nil, buckets: %{}

  @type interval :: :second | :minute
  @type state :: %{
          n: non_neg_integer,
          interval: interval(),
          buckets: Map.t()
        }

  @spec start_link(n :: non_neg_integer, interval :: :second | :minute) :: {:ok, pid}
  def start_link(n, interval) when interval in [:second, :minute] do
    GenServer.start_link(__MODULE__, struct(__MODULE__, n: n, interval: interval))
  end

  @impl true
  def init(state) do
    self() |> schedule_cleanup(state.interval)
    {:ok, state}
  end

  @doc "Returns true if request if allowed."
  @spec take(pid) :: boolean
  def take(pid), do: GenServer.call(pid, :take)

  @impl true
  def handle_call(:take, _from, state) do
    {prev_value, updated_buckets} = do_update_buckets(state.buckets, state.interval)
    {:reply, (prev_value || 0) < state.n, %{state | buckets: updated_buckets}}
  end

  def handle_call(:show_buckets, _from, state) do
    {:reply, state.buckets, state}
  end

  @spec handle_info(:cleanup, state()) :: {:noreply, state()}
  def handle_info(:cleanup, _from, state) do
    current_id = bucket_id(state.interval)
    new_buckets = state.buckets |> Enum.filter(fn {id, _} -> id >= current_id end) |> Enum.into(%{})

    self() |> schedule_cleanup(state.interval)
    {:noreply, %{state | buckets: new_buckets}}
  end

  defp do_update_buckets(buckets, interval) do
    Map.get_and_update(buckets, bucket_id(interval), fn current_value ->
      {current_value, (current_value || 0) + 1}
    end)
  end

  defp bucket_id(:second), do: System.system_time(:second)
  defp bucket_id(:minute), do: bucket_id(:second) |> div(60)
  defp bucket_id(:hour), do: bucket_id(:minute) |> div(60)

  defp cleanup_interval_sec(:second), do: 10
  defp cleanup_interval_sec(:minute), do: 10 * 60

  defp schedule_cleanup(pid, interval), do: Process.send_after(pid, :cleanup, cleanup_interval_sec(interval) * 1000)
end
