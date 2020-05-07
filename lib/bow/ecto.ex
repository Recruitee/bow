defmodule Bow.Ecto do
  @moduledoc """
  Integration of `Bow.Uploader` with `Ecto.Schema`

  ## Usage

      # Add `use Bow.Ecto` to the uploader
      defmodule MyApp.UserAvatarUploader do
        use Bow.Uploader
        use Bow.Ecto # <---- HERE

        # file.scope will be the user struct
        def store_dir(file) do
          "users/\#{file.scope.id}/avatar"
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
          field :avatar, MyApp.UserAvatarUploader.Type <-- HERE
        end

        def changeset(model \\ %__MODULE__{}, params) do
          model
          |> cast(params, [:email, :avatar])
          |> Bow.Ecto.validate() # <---- HERE
        end
      end


      # create user and save files
      changeset = User.changeset(%User{}, params)
      with {:ok, user}    <- Repo.insert(changeset),
           {:ok, user, _} <- Bow.Ecto.store(user) do
        {:ok, user}
      end

  """

  @doc """
  Customize incoming file.

  This is the place to do custom file name transformation, since `filename/2`
  is used both when uploading AND generating urls

  Example - change file name to include timestamp

      defmodule MyAvatarUploader do
        use Bow.Uploader
        use Bow.Ecto

        def cast(file) do
          ts = DateTime.utc_now |> DateTime.to_unix
          Bow.set(file, :rootname, "avatar_\#{ts}")
        end
      end


  """
  @callback cast(file :: Bow.t()) :: Bow.t()

  defmacro __using__(_) do
    uploader = __CALLER__.module

    quote do
      defmodule Type do
        use Ecto.Type

        def type, do: :string

        def cast(%Plug.Upload{path: path, filename: name}) do
          file = unquote(uploader).new(path: path, name: name)
          {:ok, unquote(uploader).cast(file)}
        end

        def cast(%Bow{} = file) do
          file = %{file | uploader: unquote(uploader)}
          {:ok, unquote(uploader).cast(file)}
        end

        def load(name) do
          {:ok, unquote(uploader).new(name: name)}
        end

        def dump(%{name: name}) do
          {:ok, name}
        end

        def embed_as(_) do
          :self
        end

        def equal?(left, right) do
          left == right
        end
      end

      @behaviour Bow.Ecto

      def cast(file), do: file
      defoverridable cast: 1
    end
  end

  defmodule StoreError do
    defexception message: nil, reason: nil
  end

  @doc """
  Validate changeset using uploader's `validate/1` function

  Example

      def changeset(model, params) do
        model
        |> cast(params, [:name, :avatar])
        |> Bow.Ecto.validate()
      end
  """
  @spec validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate(%Ecto.Changeset{} = changeset) do
    changeset
    |> extract_files()
    |> filter_uploads()
    |> Enum.reduce(changeset, &validate_upload/2)
  end

  @doc """
  Store files assigned to uploaders in Ecto Schema or Changeset.

  In order to understand how to properly use `store/1` function you need to read these few points:
  - Ecto does not have callbacks (like `after_save` etc)
  - `Ecto.Changeset.prepare_changes` is run *before* data is saved into database,
    so when inserting a new record it will **not** have a primary key (id)
  - Uploading during type casting is a bad idea
  - You do want to use record primary key in storage directory definition
  - You don't want to upload the same file multiple time, even if it hasn't changed

  You need to pass inserted/updated record since the changeset lacks primary key.
  When updating Bow.Ecto will upload only these files that were changed.

      changeset = User.create_changeset(%User{}, params)
      with  {:ok, user} <- Repo.insert(changeset)
            {:ok, _}    <- Bow.Ecto.store(user) do # pass record here, not changeset
        {:ok, user}
      end

  ### Creating

      user = User.changeset(params)
      with {:ok, user} <- Repo.insert(user),
          {:ok, user, results} <- Bow.Ecto.store(user) do
        # ...
      else
        {:error, reason} -> # handle error
      end


  ### Updating

      user = User.changeset(user, params)
      with {:ok, user} <- Repo.update(user),
          {:ok, user, results} <- Bow.Ecto.store(user) do
        # ...
      else
        {:error, reason} -> # handle error
      end

  There is also `store!/1` function that will raise error instead of returning `:ok/:error` tuple.
  """
  @spec store(Ecto.Schema.t()) :: {:ok, Ecto.Schema.t(), list} | {:error, Ecto.Schema.t(), any}
  def store(record) do
    case do_store(record) do
      {:ok, results} -> {:ok, record, results}
      {:error, results} -> {:error, record, results}
    end
  end

  @doc """
  Same as `store/1` but raises an exception in case of upload error

  ### Creating

      %User{}
      |> User.changeset(params)
      |> Repo.insert!()
      |> Bow.Ecto.store!()

  ### Updating

      user
      |> User.changeset(params)
      |> Repo.update!()
      |> Bow.Ecto.store!()
  """
  @spec store!(Ecto.Schema.t()) :: Ecto.Schema.t() | no_return
  def store!({:error, _} = err), do: err
  def store!({:ok, record}), do: {:ok, store!(record)}

  def store!(record) do
    case store(record) do
      {:ok, record, _} -> record
      {:error, _, reason} -> raise StoreError, message: inspect(reason), reason: reason
    end
  end

  @doc """
  Load file from storage

  Example
      user = Repo.get(...)
      case Bow.Ecto.load(user, :avatar) do
        {:ok, file} -> # file.path is populated with tmp path
        {:error, reason} -> # handle load error
      end

  """
  @spec load(Ecto.Schema.t(), field :: atom) :: {:ok, Bow.t()} | {:error, any}
  def load(record, field) do
    record
    |> Map.fetch!(field)
    |> do_load(record)
  end

  @doc """
  Delete record files from storage

  Example
      user = Repo.get(...)

      user
      |> Repo.delete!()
      |> Bow.Ecto.delete()

  """
  @spec delete(Ecto.Schema.t()) :: {:ok, Ecto.Schema.t()} | {:error, any}
  def delete(record) do
    with {:ok, _} <- do_delete(record) do
      {:ok, record}
    end
  end

  @doc """
  Copy file from one record to another

  Fields do not have be the same unless they use the same uploader

  Example

      user1 = Repo.get(1)
      user2 = Repo.get(2)

      Ecto.Bow.copy(user1, :avatar, user2)
  """
  @spec copy(src :: Ecto.Schema.t(), field :: atom, dst :: Ecto.Schema.t()) ::
          {:ok, Ecto.Schema.t()}
          | {:error, any}
  def copy(src, src_field, dst) do
    case Map.fetch!(src, src_field) do
      nil ->
        {:error, :missing}

      file ->
        src_file = Bow.set(file, :scope, src)
        dst_file = Bow.set(src_file, :scope, dst)
        Bow.copy(src_file, dst_file)
    end
  end

  @doc """
  Generate URL for record & field
  """
  def url(record, field), do: url(record, field, [])
  def url(record, field, opts) when is_list(opts), do: url(record, field, :original, opts)
  def url(record, field, version), do: url(record, field, version, [])

  def url(record, field, version, opts) do
    record
    |> Map.fetch!(field)
    |> do_url(record, version, opts)
  end

  @doc """
  Download remote files for given fields, i.e.
  `params["remote_avatar_url"] = "http://example.com/some/file.png"`

  Example
      changeset
      |> cast(params, [:name, :avatar])
      |> Bow.Ecto.cast_uploads(params, [:avatar])
  """
  def cast_uploads(changeset, params, fields, client \\ %Tesla.Client{}) do
    Ecto.Changeset.cast(changeset, download_params(params, fields, client), fields)
  end

  def download_params(params, fields, client \\ %Tesla.Client{}) do
    Enum.reduce(fields, params, fn field, params ->
      field = to_string(field)

      case params["remote_#{field}_url"] do
        nil ->
          params

        "" ->
          params

        url ->
          case Bow.Download.download(client, url) do
            {:ok, file} -> Map.put(params, field, file)
            _ -> params
          end
      end
    end)
  end

  defp do_load(nil, _), do: {:error, :missing}

  defp do_load(file, record) do
    file
    |> Bow.set(:scope, record)
    |> Bow.load()
  end

  defp do_url(nil, _, _, _), do: nil

  defp do_url(file, record, version, opts) do
    file
    |> Bow.set(:scope, record)
    |> Bow.url(version, opts)
  end

  defp validate_upload({field, file}, changeset) do
    case file.uploader.validate(file) do
      :ok ->
        changeset

      {:error, reason} ->
        Ecto.Changeset.add_error(changeset, field, reason)
    end
  end

  defp do_store(record) do
    record
    |> extract_files()
    |> filter_uploads()
    |> Enum.map(&store_upload(&1, record))
    |> combine_results()
  end

  defp store_upload({field, file}, record), do: {field, Bow.store(%{file | scope: record})}

  defp do_delete(record) do
    record
    |> extract_files()
    |> Enum.map(&delete_upload(&1, record))
    |> combine_results()
  end

  defp delete_upload({field, file}, record), do: {field, Bow.delete(%{file | scope: record})}

  defp extract_files(%Ecto.Changeset{changes: changes}), do: filter_files(changes)
  defp extract_files(record), do: record |> Map.from_struct() |> filter_files()

  defp filter_files(fields), do: Enum.filter(fields, &file?/1)
  defp filter_uploads(files), do: Enum.filter(files, &upload?/1)

  defp file?({_, %Bow{}}), do: true
  defp file?(_), do: false

  defp upload?({_, %Bow{path: path}}), do: path != nil

  # Similar to Bow.combine_results but flatten
  # files results for easier pattern matching
  @doc false
  def combine_results(results) do
    Enum.reduce(results, {:ok, %{}}, fn
      {key, {:error, res}}, {_, map} ->
        {:error, Map.put(map, key, res)}

      {key, {:ok, res}}, {ok, map} ->
        {ok, Map.put(map, key, res)}

      {key, res}, {ok, map} ->
        {ok, Map.put(map, key, res)}
    end)
  end
end
