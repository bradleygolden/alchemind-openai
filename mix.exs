defmodule Alchemind.OpenAI.MixProject do
  use Mix.Project

  def project do
    [
      app: :alchemind_openai,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Alchemind.OpenAI.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:alchemind, in_umbrella: true},
      {:req, "~> 0.4"},
      {:plug, "~> 1.0", only: :test}
    ]
  end
end
