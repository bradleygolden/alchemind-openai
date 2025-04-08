defmodule Alchemind.OpenAI.MixProject do
  use Mix.Project

  @version "0.1.0-rc.1"

  def project do
    [
      app: :alchemind_openai,
      version: @version,
      build_path: build_path(),
      config_path: config_path(),
      deps_path: deps_path(),
      lockfile: lockfile(),
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "AlchemindOpenAI",
      source_url: "https://github.com/bradleygolden/alchemind",
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Alchemind.OpenAI.Application, []}
    ]
  end

  defp build_path do
    if umbrella?() do
      "../../_build"
    else
      "_build"
    end
  end

  defp config_path do
    if umbrella?() do
      "../../config/config.exs"
    else
      "config/config.exs"
    end
  end

  defp deps_path do
    if umbrella?() do
      "../../deps"
    else
      "deps"
    end
  end

  defp lockfile do
    if umbrella?() do
      "../../mix.lock"
    else
      "mix.lock"
    end
  end

  defp deps do
    [
      umbrella_dep(:alchemind),
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:rustler, "~> 0.36.1", optional: true, runtime: false},
      {:rustler_precompiled, "~> 0.8"}
    ]
  end

  defp description do
    """
    An Elixir package for interacting with OpenAI's API
    """
  end

  defp package do
    [
      name: "alchemind_openai",
      files: ~w(
        lib
        native/alchemind_openai/src
        native/alchemind_openai/Cargo*
        .formatter.exs
        "checksum-*.exs"
        mix.exs
        README*
        LICENSE*
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/bradleygolden/alchemind"
      }
    ]
  end

  defp umbrella? do
    System.get_env("UMBRELLA") == "true"
  end

  defp umbrella_dep(dep) do
    if umbrella?() do
      {dep, in_umbrella: true}
    else
      {dep, "~> 0.1.0-rc1"}
    end
  end
end
