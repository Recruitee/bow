defmodule Bow.Mixfile do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :bow,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: Coverex.Task],
      package: package(),
      dialyzer: dialyzer(),

      # Docs
      name: "Bow",
      docs: docs()
    ]
  end

  defp package() do
    [
      description: "File uploads for Elixir.",
      maintainers: [],
      licenses: ["MIT"],
      links: %{
        "Github" => "https://github.com/iluminai/bow"
      }
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "https://github.com/iluminai/bow",
      source_ref: @version
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.11"},
      {:tesla, "~> 1.3"},
      {:ecto, "~> 3.6", optional: true},
      {:ecto_sql, "~> 3.6", optional: true},
      {:erlexec, "~> 1.9", optional: true},
      {:ex_aws, "~> 2.2", optional: true},
      {:ex_aws_s3, "~> 2.2", optional: true},
      {:hackney, "~> 1.17"},
      {:sweet_xml, "~> 0.6.5", optional: true},

      # testing & docs
      {:postgrex, ">= 0.0.0", only: :test},
      {:coverex, "~> 1.5", only: :test},
      {:ex_doc, "~> 0.24", only: :dev},
      {:dialyxir, "~> 1.1", only: :dev}
    ]
  end

  def aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ecto, :ex_aws, :ex_aws_s3, :erlexec]
    ]
  end
end
