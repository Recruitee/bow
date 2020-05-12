use Mix.Config

if Mix.env() == :test do
  config :bow, Bow.Repo,
    username: System.get_env("TEST_DB_USERNAME") || "development",
    password: System.get_env("TEST_DB_PASSWORD") || "",
    database: "bow_ecto_test",
    hostname: "localhost",
    pool: Ecto.Adapters.SQL.Sandbox

  config :bow, ecto_repos: [Bow.Repo]

  config :logger, level: :warn
  # fakes3 configuration
  # https://github.com/jubos/fake-s3/wiki/Supported-Clients#elixir
  config :ex_aws,
    access_key_id: ["123", :instance_role],
    secret_access_key: ["asdf", :instance_role],
    region: "fakes3"

  config :ex_aws, :s3,
    scheme: "http://",
    host: "localhost",
    port: 4567,
    bucket: "test-bucket"
end
