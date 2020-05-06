{:ok, _} = Application.ensure_all_started(:ecto_sql)
ExUnit.start(exclude: [:s3, :ecto])
