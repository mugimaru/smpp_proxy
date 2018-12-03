defmodule SmppProxy do
  @moduledoc """
  SMPP 3.4 compliant proxy.

  ## Glossary

  * SMPP (Short Message Peer-to-Peer) - Short message transfer protocol.
  * ESME (External Short Messaging Entity) - SMPP client.
  * MC (message center) - SMPP server.

  ## Structure

  smpp_proxy structure might be described as:
      ESME <-> ProxyMC <-> ProxyESME <-> MC

  ## Flow

  1. On startup smpp_proxy spawns `ProxyMC` listening for `ESME` connections on specific host and port.
  2. After `ProxyMC` receives `ESME` connection and valid bind request it spawns `ProxyESME`.
  3. After `ProxyESME` has started it is trying to connect and bind to `MC`.
  4. `ProxyESME` notifies `ProxyMC` on bind result.
  5. `ProxyMC` sends its own bind_resp to `ESME`.
  6. `ProxyMC` proxies `ESME` submits and resps to `MC` (through `ProxyESME`).
  7. `ProxyESME` proxies `MC` delivers and resps to `ESME` (through `ProxyMC`)
  """

  @doc "Starts smpp proxy with given `SmppProxy.Config`."
  @spec start(config :: SmppProxy.Config.t()) :: term

  def start(%SmppProxy.Config{} = config) do
    SmppProxy.Proxy.start_link(config)
  end
end
