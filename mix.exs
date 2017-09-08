defmodule Bow.Mixfile do
  use Mix.Project

  def project do
    [
      app: :bow,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      test_coverage: [tool: Coverex.Task]
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
      {:plug,     ">= 1.0.0"},
      # {:erlexec,  "~> 1.7.0", optional: true},
      {:ecto,     ">= 2.0.0", optional: true},

      # testing & docs
      {:coverex,        "~> 1.4.10", only: :test},
      {:ex_doc,         "~> 0.16.1", only: :dev},
      {:mix_test_watch, "~> 0.5.0",  only: :dev},
      {:dialyxir,       "~> 0.5.1",  only: :dev}
    ]
  end
end
