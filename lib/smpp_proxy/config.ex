defmodule SmppProxy.Config do
  defstruct [
    :bind_mode,
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
    bind_mode: :trx | :tx | :rx,
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

  def new(enum) do
    struct(__MODULE__, enum)
  end

  def bind_command_name(%{bind_mode: :trx}), do: :bind_transceiver
  def bind_command_name(%{bind_mode: :rx}), do: :bind_receiver
  def bind_command_name(%{bind_mode: :tx}), do: :bind_transmitter

  def bind_resp_command_name(%{bind_mode: :trx}), do: :bind_transceiver_resp
  def bind_resp_command_name(%{bind_mode: :rx}), do: :bind_receiver_resp
  def bind_resp_command_name(%{bind_mode: :tx}), do: :bind_transmitter_resp
end
