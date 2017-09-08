use Mix.Config

if Mix.env == :test do
  config :bow, Repo,
    adapter:  Ecto.Adapters.Postgres,
    username: "teamon",
    password: "",
    database: "bow_ecto_test",
    hostname: "localhost",
    port:     5433,
    pool:     Ecto.Adapters.SQL.Sandbox,
    priv:     "test/support"

  config :bow, ecto_repos: [Repo]
end
