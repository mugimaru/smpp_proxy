defmodule SmppProxy.CLI do
  def main(args \\ []) do
    app_config = config() |> Optimus.parse!(args)

    if app_config.flags[:debug] do
      Logger.configure(level: :debug) |> IO.inspect(label: :debug_flag)
    end

    SmppProxy.Config.new(app_config.options) |> SmppProxy.Proxy.start_link()
    :timer.sleep(:infinity)
  end

  defp config do
    Optimus.new!(
      name: "smpp_proxy",
      description: "SMPP 3.4 proxy",
      version: "0.1.0",
      author: "Nikita Babushkin n.babushkin@fun-box.ru",
      allow_unknown_args: false,
      parse_double_dash: true,
      flags: [
        debug: [
          long: "--debug",
          help: "Enables debug logging",
          multiple: false
        ]
      ],
      options: [
        bind_mode: [
          short: "-b",
          long: "--bind-mode",
          help: "MC/ESME bind mode. `trx` - transceiver, `rx` - receiver, `tx` - transmitter.",
          parser: fn v ->
            if v in ["trx", "rx", "tx"] do
              {:ok, String.to_atom(v)}
            else
              {:error, "Unknown bind mode"}
            end
          end,
          default: :trx
        ],
        mc_port: [
          short: "-P",
          long: "--mc-port",
          help: "TCP port for proxy MC to listen on",
          parser: :integer,
          default: 5050
        ],
        mc_system_id: [
          short: "-I",
          long: "--mc-id",
          help: "system_id for proxy MC clients",
          default: "panda"
        ],
        mc_password: [
          short: "-W",
          long: "--mc-password",
          help: "password for `mc-id`",
          required: true
        ],
        esme_host: [
          short: "-h",
          long: "--esme-host",
          help: "Ip or host of the target MC",
          default: "localhost"
        ],
        esme_port: [
          short: "-p",
          long: "--esme-port",
          help: "TCP port of the target MC",
          parser: :integer
        ],
        esme_system_id: [
          short: "-i",
          long: "--esme-id",
          help: "System id to bind to the target MC",
          required: true
        ],
        esme_password: [
          short: "-w",
          long: "--esme-password",
          help: "Password for `esme-id`",
          required: true
        ],
        senders_whitelist: [
          short: "-S",
          long: "--clients-whitelist",
          help: "Only allow specified senders (submits from source addr / delivers to destination addr)",
          multiple: true
        ],
        receivers_whitelist: [
          short: "-R",
          long: "--services-whitelist",
          help: "Only allow specified receivers (submits to destination addr / delivers from destination addr)",
          multiple: true
        ]
      ]
    )
  end
end
