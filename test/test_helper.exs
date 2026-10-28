{:ok, _} = Application.ensure_all_started(:ecto_sql)
File.mkdir_p!("tmp")
ExUnit.start(exclude: [:s3, :ecto])
