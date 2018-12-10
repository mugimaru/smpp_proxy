use Mix.Config

config :logger, level: :info
config :logger, :console, format: "$message\n"

try do
  import_config "#{Mix.env()}.exs"
rescue
  e in Mix.Config.LoadError -> e
end
