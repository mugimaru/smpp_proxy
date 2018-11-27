defmodule SmppProxyTest do
  use ExUnit.Case
  doctest SmppProxy

  test "greets the world" do
    assert SmppProxy.hello() == :world
  end
end
