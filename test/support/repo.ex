defmodule Bow.Repo do
  use Ecto.Repo, otp_app: :bow, adapter: Ecto.Adapters.Postgres
end
