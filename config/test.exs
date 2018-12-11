use Mix.Config

config :logger, level: if(System.get_env("DEBUG"), do: :debug, else: :error)
config :logger, :console, format: "$message\n"
