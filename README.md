# Bow

File uploads for Elixir

## Features

- Generate multiple dependent versions of a file
- Integration with Ecto
- Allow downloading remote files (`remote_avatar_url` params etc.)
- Multiple storage adapters (local disk, Amazon S3)

## Installation

```elixir
def deps do
  [
    {:bow, "~> 0.5.0"},

    # for AWS S3 support
    {:ex_aws, "~> 2.4"},
    {:ex_aws_s3, "~> 2.4"}
  ]
end
```

Bow requires Elixir 1.16 or newer.

## Usage

### Minimal uploader definition

```elixir
defmodule MyUploader do
  use Bow.Uploader

  # specify storage directory
  def store_dir(_file) do
    "uploads"
  end
end
```

### Full uploader example

```elixir
defmodule AttachmentUploader do
  use Bow.Uploader

  # define what versions to generate for given file
  def versions(_file) do
    [:original, :thumb]
  end


  # keep the origianal file name
  def filename(file, :original), do: file.name

  # prepend "thumb_" for thumbnail
  def filename(file, :thumb),    do: "thumb_\#{file.name}"


  # do nothing with original file
  def transform(file, :original), do: transform_original(file)

  # generate image thumbnail
  def transform(source, target, :thumb) do
    Bow.with_output(target, fn output_path ->
      case System.cmd("convert", [source.path, "-resize", "250x175^", output_path]) do
        {_, 0} -> :ok
        {cmd_output, exit_code} -> {:error, exit_code: exit_code, output: cmd_output}
      end
    end)
  end


  # specify storage directory
  def store_dir(file) do
    "attachments/\#{file.scope.id}"
  end

  # specify storage options
  def store_options(_file) do
    [acl: :public_read]
  end
end
```

### Usage with Ecto

```elixir
# Add `use Bow.Ecto` to the uploader
defmodule MyApp.UserAvatarUploader do
  use Bow.Uploader
  use Bow.Ecto # <---- HERE

  # file.scope will be the user struct
  def store_dir(file) do
    "users/#{file.scope.id}/avatar"
  end
end

# add avatar field to users table
defmodule MyApp.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar, :string
    end
  end
end


# use `MyApp.UserAvatarUploader.Type` as field type
defmodule MyApp.User do
  schema "users" do
    field :email, :string
    field :avatar, MyApp.UserAvatarUploader.Type # <-- HERE
  end

  def changeset(model \\ %__MODULE__{}, params) do
    model
    |> cast(params, [:email, :avatar])
    # uncomment to add support for remote_avatar_url params
    # |> Bow.Ecto.cast_uploads(params, [:avatar])
    |> Bow.Ecto.validate() # optional validation using uploader rules
  end
end


# create user and save files
changeset = User.changeset(%User{}, params)
with {:ok, user}    <- Repo.insert(changeset),
     {:ok, user, _} <- Bow.Ecto.store(user) do
  {:ok, user}
end
```

### Getting file URL

With standalone uploaders:

```elixir
file = MyUploader.new("path/to/file.png")

Bow.url(file)         # => url of original file
Bow.url(file, :thumb) # => url of thumb version
```

With Ecto integration:

```elixir
user = Repo.get(User, 1)

Bow.Ecto.url(user, :avatar) # url of avatar original
Bow.Ecto.url(user, :avatar, :thumb) # url of avatar thumb
Bow.Ecto.url(user, :photo, :thumb, signed: true) # you can pass storage-specific options
```

### Overwriting file name

You can change the file name using uploader's `cast/1` callback:

```elixir
defmodule TimestampUploader do
  use Bow.Uploader
  use Bow.Ecto

  def cast(file) do
    # replace "myfile.png" with "avatar_12343456.png"
    ts = DateTime.utc_now |> DateTime.to_unix
    Bow.set(file, :rootname, "avatar_#{ts}")
  end

  def store_dir(_file), do: "timestamp"
end
```

### Validation

You can overwrite `validate/1` to add validations for e.g. allowed extension.

```elixir
defmodule AvatarUploader do
  # ...
  def validate(%{ext: ext}) when ext in ~w(.jpg .png), do: :ok
  def validate(_), do: {:error, :extension_not_allowed}
  # ...
end
```

### Downloading remote files

`Bow.Ecto.cast_uploads/4` downloads files given as `remote_<field>_url` params
(e.g. `remote_avatar_url`). Files are downloaded with Erlang `:httpc` by default,
you can use any HTTP client by implementing the `Bow.Downloader` behaviour:

```elixir
# config/config.exs
config :bow, downloader: MyApp.BowDownloader
```

See `Bow.Downloader` docs for an example based on Req.

### Processing files

`transform/3` can generate the version in any way you like. `Bow.with_output/2` helps with
the boring part: it gives you a temporary output path (with the target extension, so tools like
ImageMagick or libvips pick the right format), checks the file was written and sets it on the target.

With [Vix](https://hexdocs.pm/vix):

```elixir
def transform(source, target, :thumb) do
  Bow.with_output(target, fn output_path ->
    with {:ok, thumb} <- Vix.Vips.Operation.thumbnail(source.path, 250) do
      Vix.Vips.Image.write_to_file(thumb, output_path)
    end
  end)
end
```

With an external program:

```elixir
def transform(source, target, :thumb) do
  Bow.with_output(target, fn output_path ->
    case System.cmd("convert", [source.path, "-resize", "250x175^", output_path]) do
      {_, 0} -> :ok
      {cmd_output, exit_code} -> {:error, exit_code: exit_code, output: cmd_output}
    end
  end)
end
```

`System.cmd/3` does not support timeouts. Version generation is limited by `:version_timeout`,
but the OS process may keep running after it. If you need to kill it, use a library like
[MuonTrap](https://hexdocs.pm/muontrap) or [erlexec](https://hexdocs.pm/erlexec).

### Using Bow in test environment

It is best to use local storage adapter when testing.

```elixir
# config/test.exs
config :bow,
  storage: Bow.Storage.Local,
  storage_prefix: "tmp/bow/"
```

## Running Bow tests

```bash
mix test
```

#### Testing ecto integration

```bash
# start postgres, or use your own and set TEST_DB_USERNAME, TEST_DB_PASSWORD, TEST_DB_HOST, TEST_DB_PORT
docker run --rm -d -p 5432:5432 -e POSTGRES_USER=development -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16-alpine

# create test database
MIX_ENV=test mix ecto.create

# run tests
mix test --only ecto
```

#### Testing S3 adapter

```bash
# start S3 mock server
docker run --rm -d -p 4567:9090 -e COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS=test-bucket adobe/s3mock

# run tests
mix test --only s3
```
