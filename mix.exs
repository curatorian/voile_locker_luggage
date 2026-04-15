defmodule VoileLockerLuggage.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/curatorian/voile_locker_luggage"

  def project do
    [
      app: :voile_locker_luggage,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      name: "VoileLockerLuggage",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "Visitor locker & luggage management plugin for the Voile GLAM library system."
  end

  defp package do
    [
      name: "voile_locker_luggage",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Voile" => "https://github.com/curatorian/voile"
      },
      maintainers: ["Chrisna Adhi Pranoto"],
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.3"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
