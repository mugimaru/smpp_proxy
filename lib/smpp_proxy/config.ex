defmodule SmppProxy.Config do
  @moduledoc """
    Proxy configuration. See `SmppProxy.CLI`.
  """

  defstruct [
    :mc_port,
    :mc_system_id,
    :mc_password,
    :esme_host,
    :esme_port,
    :esme_system_id,
    :esme_password,
    :senders_whitelist,
    :receivers_whitelist
  ]

  @type t :: %__MODULE__{
          mc_port: integer,
          mc_system_id: String.t(),
          mc_password: String.t(),
          esme_host: String.t(),
          esme_port: integer,
          esme_system_id: String.t(),
          esme_password: String.t(),
          senders_whitelist: list(String.t()),
          receivers_whitelist: list(String.t())
        }

  @spec new(Enumerable.t()) :: t()
  def new(enum) do
    struct(__MODULE__, enum)
  end
end
