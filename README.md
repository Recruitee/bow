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
    {:bow, "~> 0.1.0"},

    # for AWS S3 support
    {:ex_aws, "~> 2.0"},
    {:ex_aws_s3, "~> 2.0"},

    # for Bow.Exec
    {:erlexec,  "~> 1.7.0"}
  ]
end
```

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
    Bow.Exec.exec source, target,
      "convert ${input} -strip -gravity Center -resize 250x175^ -extent 250x175 ${output}"
  end


  # specify storage directory
  def store_dir(file) do
    "attachments/\#{file.scope.id}"
  end

  # specify storage options
  def store_options(_file) do
    %{acl: :private}
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
# edit config/config.exs

# create test database
MIX_ENV=test mix ecto.create

# run tests
mix test --only ecto
```

#### Testing S3 adapter

```bash
# install fake-s3 gem
gem install fakes3

# start fake-s3 server
fakes3 -r tmp/s3 -p 4567

# run tests
mix test --only s3
```
