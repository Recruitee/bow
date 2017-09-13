use Mix.Config

if Mix.env == :test do
  config :bow, Bow.Repo,
    adapter:  Ecto.Adapters.Postgres,
    username: "teamon",
    password: "",
    database: "bow_ecto_test",
    hostname: "localhost",
    port:     5433,
    pool:     Ecto.Adapters.SQL.Sandbox

  config :bow, ecto_repos: [Bow.Repo]

  config :logger, level: :error
end
