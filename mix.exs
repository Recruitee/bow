defmodule Bow.Mixfile do
  use Mix.Project

  def project do
    [
      app: :bow,
      version: "0.1.0",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env),
      start_permanent: Mix.env == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: Coverex.Task]
    ]
  end

  def application do
    [
      extra_applications: [:logger] ++ applications(Mix.env)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp applications(:test), do: [:ecto, :postgrex]
  defp applications(_), do: []

  defp deps do
    [
      {:plug,     ">= 1.0.0"},
      # {:erlexec,  "~> 1.7.0", optional: true},
      {:ecto,     ">= 2.0.0", optional: true},

      # testing & docs
      {:postgrex,       ">= 0.0.0",  only: :test},
      {:coverex,        "~> 1.4.10", only: :test},
      {:ex_doc,         "~> 0.16.1", only: :dev},
      {:mix_test_watch, "~> 0.5.0",  only: :dev},
      {:dialyxir,       "~> 0.5.1",  only: :dev}
    ]
  end

  def aliases do
    ["ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
     "ecto.reset": ["ecto.drop --quiet", "ecto.setup"]]
  end
end
