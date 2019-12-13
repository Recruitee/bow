defmodule Bow.Mixfile do
  use Mix.Project

  def project do
    [
      app: :bow,
      version: "0.2.1",
      elixir: "~> 1.3",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: Coverex.Task]
    ]
  end

  def application do
    [
      applications: [:logger, :plug, :tesla] ++ applications(Mix.env())
    ]

    # TODO: Uncomment wneh dropping support for elixir 1.3
    # [
    #   extra_applications: [:logger] ++ applications(Mix.env)
    # ]
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
      {:tesla, "~> 0.7", github: "teamon/tesla", branch: "master"},
      {:ecto, "~> 3.2", optional: true},
      {:ecto_sql, "~> 3.2", optional: true},
      {:erlexec, "~> 1.9.0", optional: true},
      {:ex_aws, "~> 2.0", optional: true},
      {:ex_aws_s3, "~> 2.0", optional: true},
      {:sweet_xml, "~> 0.6.5", optional: true},

      # testing & docs
      {:postgrex, ">= 0.0.0", only: :test},
      {:coverex, "~> 1.4.10", only: :test},
      {:ex_doc, "~> 0.16.1", only: :dev},
      {:mix_test_watch, "~> 0.5.0", only: :dev},
      {:dialyxir, "~> 0.5.1", only: :dev}
    ]
  end

  def aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"]
    ]
  end
end
