defmodule SmppProxy do
  def test do
    {:ok, mc} = FakeMC.start(5051)
    {:ok, proxy} = SmppProxy.Proxy.start_link(%{mc_port: 5050, esme_port: 5051, esme_host: "localhost"})

    {:ok, {mc, proxy}}
  end
end
