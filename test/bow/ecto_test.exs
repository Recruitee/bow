defmodule Bow.EctoTest do
  use ExUnit.Case

  setup do
    Bow.Storage.Local.reset!
    :ok
  end

  @upload_bear %Plug.Upload{path: "test/files/bear.png", filename: "bear.png"}

  defmodule AvatarUploader do
    use Bow.Uploader
    use Bow.Ecto

    def versions(_file) do
      [:original, :thumb]
    end

    def store_dir(file) do
      "users/#{file.scope.id}"
    end
  end

  defmodule MyUser do
    use Ecto.Schema

    schema "this table does not exist" do
      field :name,    :string
      field :avatar,  AvatarUploader.Type
    end
  end

  test "casting" do
    params = %{
      "name"    => "Jon",
      "avatar"  => @upload_bear
    }
    user = Ecto.Changeset.cast(%MyUser{id: 1}, params, [:name, :avatar])

    assert %Bow{name: "bear.png"} = user.changes.avatar

    assert {:ok, user, results} =
      user
      |> Ecto.Changeset.apply_changes() # fake Repo.insert
      |> Bow.Ecto.store()

    assert results[:avatar] == {:ok, [original: :ok, thumb: :ok]}
    assert %Bow{name: "bear.png"} = user.avatar
    assert File.exists?("tmp/bow/users/1/bear.png")

    assert AvatarUploader.url({user.avatar, user}) == "tmp/bow/users/1/bear.png"
    assert AvatarUploader.url({user.avatar, user}, :thumb) == "tmp/bow/users/1/thumb_bear.png"
  end

#   import Mock

#   test_with_mock "remote_file_url handling", Bow.Download, [
#     get: fn _ ->
#       %{
#         status: 200,
#         body: "",
#         headers: %{"Content-Type" => "image/png"}
#       }
#     end
#   ] do
#     params = %{
#       "name" => "Jon",
#       "remote_avatar_url" => "http://img.example.com/file.png"
#     }
#
#     user = %MyUser{id: 1}
#       |> Bow.Ecto.cast_uploads(params, [:avatar])
#
#     assert %Bow{name: "file.png"} = user.changes.avatar
#   end
end
