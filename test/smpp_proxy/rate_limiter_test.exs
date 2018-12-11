defmodule SmppProxy.RateLimiterTest do
  use ExUnit.Case, async: true
  alias SmppProxy.RateLimiter

  test "controls requests count" do
    {:ok, pid} = RateLimiter.start_link(5, :second)
    assert [true, true, true, true, true, false] == Enum.map(1..6, fn _ -> RateLimiter.take(pid) end)
    :timer.sleep(1000)
    assert true == RateLimiter.take(pid)
  end
end
