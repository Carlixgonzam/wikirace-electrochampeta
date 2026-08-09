defmodule Player.MixProject do
  use Mix.Project

  def project do
    [
      app: :player,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Player.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Only Req and Floki. This is the entire dependency surface a crawler is
  # allowed to add to; everything else must be OTP: GenServer,
  # DynamicSupervisor, ETS, Erlang distribution.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:floki, "~> 0.38"}
    ]
  end
end
