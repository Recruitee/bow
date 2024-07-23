defmodule Bow.DownloadTest do
  use ExUnit.Case

  @file_cat "test/files/cat.jpg"

  import Bow.Download, only: [download: 2]

  setup do
    client =
      Tesla.client([Tesla.Middleware.FollowRedirects], fn env ->
        case env do
          %{url: "http://example.com/cat.png"} ->
            {:ok,
             %{
               env
               | status: 200,
                 body: File.read!(@file_cat),
                 headers: [{"content-type", "image/png"}]
             }}

          %{url: "http://example.com/kitten.png"} ->
            {:ok, %{env | status: 301, headers: [{"location", "http://example.com/cat.png"}]}}

          %{url: "http://example.com/loop.png"} ->
            {:ok, %{env | status: 301, headers: [{"location", "http://example.com/loop.png"}]}}

          %{url: "http://example.com/notype.png"} ->
            {:ok, %{env | status: 200, body: File.read!(@file_cat)}}

          %{url: "http://example.com/noext"} ->
            {:ok, %{env | status: 200, body: File.read!(@file_cat)}}

          %{url: "http://example.com/u" <> _} ->
            {:ok,
             %{
               env
               | status: 200,
                 body: File.read!(@file_cat),
                 headers: [{"content-type", "image/png"}]
             }}

          %{url: "http://example.com"} ->
            {:ok,
             %{
               env
               | status: 200,
                 body: File.read!(@file_cat),
                 headers: [{"content-type", "image/png"}]
             }}

          %{url: "http://example.com/dog.jpg"} ->
            {:ok,
             %{
               env
               | status: 200,
                 body: File.read!(@file_cat),
                 headers: [{"content-type", "example/dog/nope"}]
             }}

          %{url: "http://example.com/.weird-path"} ->
            {:ok,
             %{
               env
               | status: 200,
                 body: File.read!(@file_cat),
                 headers: [{"content-type", "image/png"}]
             }}

          _ ->
            {:ok, %{env | status: 404, body: "NotFound"}}
        end
      end)

    {:ok, client: client}
  end

  test "regular file", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/cat.png")
    assert file.name == "cat.png"
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file with redirect", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/kitten.png")
    assert file.name == "cat.png"
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "too many redirects", %{client: client} do
    assert {:error, %Tesla.Error{}} = download(client, "http://example.com/loop.png")
  end

  test "file without content type", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/notype.png")
    assert file.name == "notype.png"
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file without extension", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/noext")
    assert file.name == "noext"
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file with invalid content type", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/dog.jpg")
    assert file.name == "dog.jpg"
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "url with path starting with dot", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/.weird-path")
    assert Regex.match?(~r/.+\.png/, file.name)
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file not found", %{client: client} do
    assert {:error, %{status: 404}} = download(client, "http://example.com/nope")
  end

  test "without file path", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com")

    uuid_name = file.name |> String.split(".") |> Enum.at(0)

    assert {:ok, _} = Ecto.UUID.dump(uuid_name)
    assert file.path != nil
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "dynamic URL", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/u/91372?v=3&s=460")
    assert file.name == "91372.png"
  end
end
