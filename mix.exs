defmodule SmppProxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :smpp_proxy,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:smppex, "~> 2.0"},
      {:credo, "~> 0.10.0", only: [:dev, :test], runtime: false}
    ]
  end
end
