defmodule Bow.Mixfile do
  use Mix.Project

  @version "0.4.2"

  def project do
    [
      app: :bow,
      version: @version,
      elixir: "~> 1.4",
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

  def application do
    [
      extra_applications: [:logger] ++ applications(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp applications(:test) do
    [
      # Bow.Ecto
      :ecto,
      :postgrex,
      # Bow.Exec
      :erlexec,
      # Bow.Storage.S3
      :hackney,
      :sweet_xml
    ]
  end

  defp applications(_), do: []

  defp deps do
    [
      {:plug, "~> 1.0"},
      {:tesla, "~> 1.0"},
      {:ecto, "~> 3.2", optional: true},
      {:ecto_sql, "~> 3.2", optional: true},
      {:erlexec, "~> 1.19", optional: true},
      {:ex_aws, "~> 2.0", optional: true},
      {:ex_aws_s3, "~> 2.0", optional: true},
      {:sweet_xml, "~> 0.7", optional: true},

      # testing & docs
      {:postgrex, ">= 0.0.0", only: :test},
      {:coverex, "~> 1.5", only: :test},
      {:ex_doc, "~> 0.21", only: :dev},
      {:mix_test_watch, "~> 1.1", only: :dev},
      {:dialyxir, "~> 1.1", only: :dev}
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
      plt_add_apps: [:ecto, :ex_aws, :ex_aws_s3, :erlexec]
    ]
  end
end
