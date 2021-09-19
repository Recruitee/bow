defmodule Bow.Mixfile do
  use Mix.Project

  @source_url "https://github.com/recruitee/bow"
  @version "0.3.3"

  def project do
    [
      app: :bow,
      name: "Bow",
      version: @version,
      elixir: "~> 1.3",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: dialyzer(),
      test_coverage: [tool: Coverex.Task]
    ]
  end

  def application do
    [
      applications: [:logger, :plug, :tesla] ++ applications(Mix.env())
    ]
  end

  # TODO: Uncomment when we dropping support for elixir 1.3
  # def application do
  #   [
  #     extra_applications: [:logger] ++ applications(Mix.env)
  #   ]
  # end

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
      {:erlexec, "~> 1.9.0", optional: true},
      {:ex_aws, "~> 2.0", optional: true},
      {:ex_aws_s3, "~> 2.0", optional: true},
      {:sweet_xml, "~> 0.6.5", optional: true},

      # testing & docs
      {:postgrex, ">= 0.0.0", only: :test},
      {:coverex, "~> 1.4.10", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 0.5.0", only: :dev},
      {:dialyxir, "~> 1.0", only: :dev}
    ]
  end

  def aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"]
    ]
  end

  defp package do
    [
      description: "File uploads for Elixir.",
      maintainers: ["Kacper Pucek"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/bow/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      source_url: @source_url,
      source_ref: @version,
      formatters: ["html"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ecto, :ex_aws, :ex_aws_s3, :erlexec]
    ]
  end
end
