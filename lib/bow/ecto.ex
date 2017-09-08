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

        @required_fields ~w(email)
        @optional_fields ~w(avatar)

        def changeset(model, params \\ %{}) do
          model
          |> cast(params, @required_fields, @optional_fields)
          |> Bow.Ecto.validate # <---- HERE
        end
      end


      # create user and save files
      changeset = User.changeset(%User{}, params)
      with {:ok, user}  <- Repo.insert(changeset),
           {:ok, _}     <- Bow.Ecto.store(user) do
        {:ok, user}
      end

  """

  @doc """
  Customize incoming file.

  This is the place to do custom file name transformation, since `filename/2` is used both when uploading AND generating urls

  Example - change file name to include timestamp

      defmodule MyAvatarUploader do
        use Bow.Uploader
        use Bow.Ecto

        def cast(file) do
          file |> Bow.set_name("avatar_\#{DateTime.utc_now |> DateTime.to_unix}\#{file.ext}")
        end
      end


  """
  @callback cast(file :: Bow.t) :: Bow.t


  defmacro __using__(_) do
    uploader = __CALLER__.module

    quote do
      defmodule Type do
        @behaviour Ecto.Type

        def type, do: :string

        def cast(%Plug.Upload{path: path, filename: name}) do
        #   file = Bow.new(path, name: name, uploader: unquote(uploader)) |> unquote(uploader).cast
        #   {:ok, file}
        end

        # def cast(%Bow{} = file) do
        #   file = %{file | uploader: unquote(uploader), path: nil} |> unquote(uploader).cast
        #   {:ok, file}
        # end

        def load(name) do
        #   {:ok, Bow.new(nil, name: name, uploader: unquote(uploader))}
        end

        def dump(%{name: name}) do
          # {:ok, name}
        end
      end

      # def validate_changeset_field(changeset, field, file) do
      #   case validate(file) do
      #     {:error, reason}  -> %{changeset | errors: changeset.errors ++ [{field, {reason, []}}], valid?: false}
      #     :ok               -> changeset
      #   end
      # end


      # @behaviour Bow.Ecto
      #
      # def cast(file), do: file
      # defoverridable [cast: 1]
    end
  end



  alias Ecto.Changeset


  @doc """
  Validate changeset using uploader's `validate/1` function

  Example

      def changeset(model, params \\ %{}) do
        model
        |> cast(params, @required_fields, @optional_fields)
        |> Bow.Ecto.validate
      end
  """
  # def validate(%Changeset{} = changeset) do
  #   changeset
  #   |> extract
  #   |> Enum.reduce(changeset, &validate_upload/2)
  # end


  @doc """
  Store files assigned to uploaders in Ecto Schema or Changeset.

  In order to understand how to properly use `store/1` function you need to read these few points:
  - Ecto does not have callbacks (like `after_save` etc)
  - `Ecto.Changeset.prepare_changes` is run *before* data is saved into database, so when inserting a new record it will **not** have a primary key (id)
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

  ## Using with pipe

  `Bow.Ecto` understands pipes so you can use and it will return:
    - in case of `{:ok, record}` - `{:ok, record, store_results}`
    - in case of `{:error, reason}` - `{:error, reason}` (no uploading)


  ### Creating

      %User{}
      |> User.changeset(params)
      |> Repo.insert
      |> Bow.Ecto.store


  ### Updating

      user
      |> User.changeset(params)
      |> Repo.update
      |> Bow.Ecto.store

  There is also `store!/1` function that will raise error instead of returning `:ok/:error` tuple.
  """
  # @spec store(input :: ({:ok, Ecto.Schema.t} | {:error, any} | Ecto.Schema.t)) ::
  #   {:ok, Ecto.Schema.t, {:ok, any}} |
  #   {:ok, Ecto.Schema.t, {:error, any}} |
  #   {:ok, results :: any} |
  #   {:error, reason :: any}
  # def store({:error, _} = err), do: err
  # def store({:ok, record}),     do: {:ok, record, store(record)}
  # def store(record),            do: store_uploads(extract(record), record)

  @doc """
  Same as `store/1` but raises an exception in case of upload error
  """
  # @spec store!(input :: ({:ok, Ecto.Schema.t} | {:error, any} | Ecto.Schema.t)) ::
  #   {:ok, Ecto.Schema.t} | {:error, any} | any
  # def store!({:error, _} = err), do: err
  # def store!({:ok, record}) do
  #   store!(record)
  #   {:ok, record}
  # end
  # def store!(input) do
  #   {:ok, _} = store(input) # TODO: Raise proper error
  # end

  # defp validate_upload({field, file}, changeset) do
  #   file.uploader.validate_changeset_field(changeset, field, file)
  # end
  #
  # defp store_uploads(uploads, scope) do
  #   uploads
  #   |> Enum.map(&store_upload(&1, scope))
  #   |> Bow.combine_results
  # end

  # defp store_upload({field, file}, scope), do: {field, Bow.store(%{file | scope: scope})}
  #
  # defp extract(%Changeset{} = changeset) do
  #   changeset.changes
  #   |> Enum.filter(&upload?/1)
  # end
  # defp extract(record) do
  #   record
  #   |> Map.from_struct
  #   |> Enum.filter(&upload?/1)
  # end

  # defp upload?({_, %Bow{path: path}}) when not is_nil(path), do: true
  # defp upload?(_), do: false

  ## REMOTE FILE URL

  import Ecto.Changeset, only: [cast: 3]

  # def cast_uploads(changeset, params, fields) do
  #   cast(changeset, download_remote_file_params(params, fields), fields)
  # end

  # def download_remote_file_params(params, fields) do
  #   Enum.reduce(fields, params, fn f, ps ->
  #     f = to_string(f)
  #     url = ps["remote_#{f}_url"]
  #     if url && url != "" do
  #       case Bow.download_remote_file(url) do
  #         {:ok, upload} -> Map.put(ps, f, upload)
  #         _             -> ps
  #       end
  #     else
  #       ps
  #     end
  #   end)
  # end
end
