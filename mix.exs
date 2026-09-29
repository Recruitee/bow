defmodule Bow.Mixfile do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :bow,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      dialyzer: dialyzer(),

      # Docs
      name: "Bow",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl, :public_key]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.14"},
      {:mime, "~> 1.0 or ~> 2.0"},
      {:ecto, "~> 3.10", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:ex_aws, "~> 2.4", optional: true},
      {:ex_aws_s3, "~> 2.4", optional: true},
      {:sweet_xml, "~> 0.7", optional: true},

      # testing & docs
      {:jason, "~> 1.4", only: :test},
      {:req, "~> 0.5", only: :test},
      {:bandit, "~> 1.0", only: :test},
      {:postgrex, ">= 0.0.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  def aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"]
    ]
  end

  defp package() do
    [
      description: "File uploads for Elixir.",
      maintainers: [],
      licenses: ["MIT"],
      links: %{
        "Github" => "https://github.com/recruitee/bow"
      }
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "https://github.com/recruitee/bow",
      source_ref: @version
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ecto, :ex_aws, :ex_aws_s3]
    ]
  end
end
