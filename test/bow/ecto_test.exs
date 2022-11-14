defmodule Bow.EctoTest do
  use ExUnit.Case

  @moduletag :ecto

  alias Bow.Repo

  setup_all do
    {:ok, _} = Repo.start_link()
    :ok
  end

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, _} =
      Ecto.Adapters.SQL.query(
        Repo,
        """
          CREATE TEMPORARY TABLE "bow-test-users" (
            id      SERIAL PRIMARY KEY,
            name    VARCHAR(255),
            avatar  VARCHAR(255),
            cover_image  VARCHAR(255)
          )
          ON COMMIT DROP
        """,
        []
      )

    Bow.Storage.Local.reset!()
    :ok
  end

  defmodule Avatar do
    use Bow.Uploader
    use Bow.Ecto

    def versions(_file) do
      [:original, :thumb]
    end

    def validate(%{ext: ".png"}), do: :ok
    def validate(_), do: {:error, "Only PNG allowed"}

    def store_dir(file) do
      "users/#{file.scope.id}"
    end
  end

  defmodule CoverImage do
    use Bow.Uploader
    use Bow.Ecto

    def versions(_file) do
      [:original, :thumb]
    end

    def validate(%{ext: ".png"}), do: :ok
    def validate(_), do: {:error, "Only PNG allowed"}

    def store_dir(file) do
      "users/#{file.scope.id}"
    end

    def assets_host do
      "https://bow.dev/"
    end
  end

  defmodule User do
    use Ecto.Schema

    schema "bow-test-users" do
      field(:name, :string)
      field(:avatar, Avatar.Type)
      field(:cover_image, CoverImage.Type)
    end

    def changeset(struct \\ %__MODULE__{}, params) do
      struct
      |> Ecto.Changeset.cast(params, [:name, :avatar, :cover_image])
    end
  end

  @upload_bear %Plug.Upload{path: "test/files/bear.png", filename: "bear.png"}
  @upload_memo %Plug.Upload{path: "test/files/memo.txt", filename: "memo.txt"}

  describe "Type internals" do
    test "type/0" do
      assert Avatar.Type.type() == :string
    end

    test "cast/1" do
      assert {:ok, %Bow{} = file} = Avatar.Type.cast(@upload_bear)
      assert file.name == "bear.png"
      assert file.path != nil
    end

    test "load/1" do
      assert {:ok, %Bow{} = file} = Avatar.Type.load("bear.png")
      assert file.name == "bear.png"
      assert file.path == nil
    end
  end

  describe "Custom cast" do
    defmodule Timestamp do
      use Bow.Uploader
      use Bow.Ecto

      def cast(file) do
        ts = DateTime.utc_now() |> DateTime.to_unix()
        Bow.set(file, :rootname, "avatar_#{ts}")
      end

      def store_dir(_file), do: "timestamp"
    end
  end

  describe "Inside schema" do
    test "do not store when not given" do
      assert {:ok, user, results} =
               User.changeset(%{"name" => "Jon"})
               |> Repo.insert!()
               |> Bow.Ecto.store()

      assert user.avatar == nil
      assert results == %{}
    end

    test "cast when insert/update" do
      user = User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})

      assert %Bow{name: "bear.png"} = user.changes.avatar

      assert {:ok, user, results} =
               user
               |> Repo.insert!()
               |> Bow.Ecto.store()

      assert results == %{
               avatar: %{original: :ok, thumb: :ok}
             }

      assert %Bow{name: "bear.png"} = user.avatar
      assert File.exists?("tmp/bow/users/#{user.id}/bear.png")

      assert Bow.Ecto.url(user, :avatar) == "tmp/bow/users/#{user.id}/bear.png"
      assert Bow.Ecto.url(user, :avatar, :thumb) == "tmp/bow/users/#{user.id}/thumb_bear.png"
    end

    test "cast when insert/update custom assets host" do
      user = User.changeset(%{"name" => "Jon", "cover_image" => @upload_bear})

      assert %Bow{name: "bear.png"} = user.changes.cover_image

      assert {:ok, user, results} =
               user
               |> Repo.insert!()
               |> Bow.Ecto.store()

      assert results == %{
               cover_image: %{original: :ok, thumb: :ok}
             }

      assert %Bow{name: "bear.png"} = user.cover_image
      assert File.exists?("tmp/bow/users/#{user.id}/bear.png")

      assert Bow.Ecto.url(user, :cover_image) ==
               "https://bow.dev/" <> "tmp/bow/users/#{user.id}/bear.png"

      assert Bow.Ecto.url(user, :cover_image, :thumb) ==
               "https://bow.dev/" <> "tmp/bow/users/#{user.id}/thumb_bear.png"
    end

    test "load avatar" do
      # insert user with avatar
      User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
      |> Repo.insert!()
      |> Bow.Ecto.store()

      # test loading
      user = Repo.one(User)
      assert %Bow{name: "bear.png", path: nil} = user.avatar
    end

    test "load when empty" do
      # insert user without
      User.changeset(%{"name" => "Jon"})
      |> Repo.insert!()
      |> Bow.Ecto.store()

      # test loading
      user = Repo.one(User)
      assert user.avatar == nil
    end

    test "load with scope" do
      # insert user with avatar
      {:ok, user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      # test load
      assert {:ok, file} = Bow.Ecto.load(user, :avatar)
      assert file.path == "tmp/bow/users/#{user.id}/bear.png"
    end

    test "delete when empty" do
      # insert user with avatar
      {:ok, _user, _} =
        User.changeset(%{"name" => "Jon"})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      # test delete
      assert {:ok, _user} =
               User
               |> Repo.one()
               |> Repo.delete!()
               |> Bow.Ecto.delete()
    end

    test "delete avatar" do
      # insert user with avatar
      {:ok, _user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      # test delete
      assert {:ok, user} =
               User
               |> Repo.one()
               |> Repo.delete!()
               |> Bow.Ecto.delete()

      refute File.exists?("tmp/bow/users/#{user.id}/bear.png")
    end

    test "do not store when updating" do
      # insert user with avatar
      {:ok, user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      # remove file
      File.rm("tmp/bow/users/#{user.id}/bear.png")

      # test update
      assert {:ok, user} =
               User
               |> Repo.one()
               |> User.changeset(%{"name" => "Snow"})
               |> Repo.update()

      assert user.name == "Snow"

      # test file is NOT uploaded
      refute File.exists?("tmp/bow/users/#{user.id}/bear.png")
    end

    test "store file with other user (copy)" do
      # insert user with avatar
      {:ok, _user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      user = User |> Repo.one()

      {:ok, file} = Bow.Ecto.load(user, :avatar)

      {:ok, new_user, _} =
        User.changeset(%{"name" => "Snow", "avatar" => file})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      assert File.exists?("tmp/bow/users/#{user.id}/bear.png")
      assert File.exists?("tmp/bow/users/#{new_user.id}/bear.png")

      assert File.read!("tmp/bow/users/#{user.id}/bear.png") ==
               File.read!("tmp/bow/users/#{new_user.id}/bear.png")
    end
  end

  describe "Validation" do
    test "allow empty file" do
      user =
        User.changeset(%{"name" => "Jon"})
        |> Bow.Ecto.validate()

      assert user.valid? == true
    end

    test "allow png file" do
      user =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Bow.Ecto.validate()

      assert user.valid? == true
    end

    test "do not allow txt file" do
      user =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_memo})
        |> Bow.Ecto.validate()

      assert user.valid? == false
      assert user.errors[:avatar] == {"Only PNG allowed", []}
    end
  end

  describe "Remote file URLs" do
    defp client do
      Tesla.client([], fn
        %{url: "http://example.com/bear.png"} = env ->
          {:ok,
           %{
             env
             | status: 200,
               body: File.read!("test/files/bear.png"),
               headers: [{"Content-Type", "image/png"}]
           }}

        env ->
          {:ok, %{env | status: 404}}
      end)
    end

    test "empty params" do
      params = %{}
      user = %User{} |> Bow.Ecto.cast_uploads(params, [:avatar], client())
      assert user.changes == %{}
    end

    test "empty string as param" do
      params = %{"remote_avatar_url" => ""}
      user = %User{} |> Bow.Ecto.cast_uploads(params, [:avatar], client())
      assert user.changes == %{}
    end

    test "invalid URL" do
      params = %{"remote_avatar_url" => "some-ribbish"}
      user = %User{} |> Bow.Ecto.cast_uploads(params, [:avatar], client())
      assert user.changes == %{}
    end

    test "valid URL" do
      params = %{"remote_avatar_url" => "http://example.com/bear.png"}
      user = %User{} |> Bow.Ecto.cast_uploads(params, [:avatar], client())
      assert %Bow{} = user.changes.avatar
    end
  end

  describe "#url" do
    setup do
      {:ok, user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      {:ok, user: user}
    end

    test "original", %{user: user} do
      assert Bow.Ecto.url(user, :avatar) == "tmp/bow/users/#{user.id}/bear.png"
    end

    test "original + opts", %{user: user} do
      assert Bow.Ecto.url(user, :avatar, sign: true) == "tmp/bow/users/#{user.id}/bear.png"
    end

    test "version", %{user: user} do
      assert Bow.Ecto.url(user, :avatar, :thumb) == "tmp/bow/users/#{user.id}/thumb_bear.png"
    end

    test "version + opts", %{user: user} do
      assert Bow.Ecto.url(user, :avatar, :thumb, sign: true) ==
               "tmp/bow/users/#{user.id}/thumb_bear.png"
    end

    test "nil field" do
      assert Bow.Ecto.url(%User{}, :avatar) == nil
    end

    test "raise on invalid field" do
      assert_raise KeyError, fn -> Bow.Ecto.url(%User{}, :nope) end
    end
  end

  describe "Copy" do
    test "copy avatar with all versions" do
      {:ok, user, _} =
        User.changeset(%{"name" => "Jon", "avatar" => @upload_bear})
        |> Repo.insert!()
        |> Bow.Ecto.store()

      clone =
        User.changeset(%{"name" => "Bran"})
        |> Repo.insert!()

      assert {:ok, results} = Bow.Ecto.copy(user, :avatar, clone)

      assert results == %{
               original: :ok,
               thumb: :ok
             }

      assert File.exists?("tmp/bow/users/#{user.id}/bear.png")
      assert File.exists?("tmp/bow/users/#{clone.id}/bear.png")
      assert File.exists?("tmp/bow/users/#{user.id}/thumb_bear.png")
      assert File.exists?("tmp/bow/users/#{clone.id}/thumb_bear.png")
    end
  end

  describe "ok/error tuples" do
    test "handle error tuples" do
      assert Bow.Ecto.store!({:error, :reason}) == {:error, :reason}
    end

    test "handle ok tuple" do
      user = %User{}
      assert Bow.Ecto.store!({:ok, user}) == {:ok, user}
    end
  end

  describe "combine_results/1" do
    test "with error" do
      assert Bow.Ecto.combine_results(
               avatar: {:error, %{original: :ok, thumb: {:error, "oups"}}},
               photo: {:ok, %{original: :ok}}
             ) ==
               {:error,
                %{
                  avatar: %{original: :ok, thumb: {:error, "oups"}},
                  photo: %{original: :ok}
                }}
    end

    test "all ok" do
      assert Bow.Ecto.combine_results(
               avatar: {:ok, %{thumb: :ok}},
               photo: {:ok, %{original: :ok}}
             ) ==
               {:ok,
                %{
                  avatar: %{thumb: :ok},
                  photo: %{original: :ok}
                }}
    end
  end
end
