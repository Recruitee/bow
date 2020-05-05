defmodule Bow.DownloadTest do
  use ExUnit.Case

  @file_cat "test/files/cat.jpg"

  import Bow.Download, only: [download: 2]

  setup do
    client =
      Tesla.client([], fn env ->
        case env do
          %{url: "http://example.com/cat.png"} ->
            %{
              env
              | status: 200,
                body: File.read!(@file_cat),
                headers: %{"Content-Type" => "image/png"}
            }

          %{url: "http://example.com/kitten.png"} ->
            %{env | status: 301, headers: %{"Location" => "http://example.com/cat.png"}}

          %{url: "http://example.com/loop.png"} ->
            %{env | status: 301, headers: %{"Location" => "http://example.com/loop.png"}}

          %{url: "http://example.com/notype.png"} ->
            %{env | status: 200, body: File.read!(@file_cat)}

          %{url: "http://example.com/noext"} ->
            %{env | status: 200, body: File.read!(@file_cat)}

          %{url: "http://example.com/u" <> _} ->
            %{
              env
              | status: 200,
                body: File.read!(@file_cat),
                headers: %{"Content-Type" => "image/png"}
            }

          %{url: "http://example.com/dog.jpg"} ->
            %{
              env
              | status: 200,
                body: File.read!(@file_cat),
                headers: %{"Content-Type" => "example/dog/nope"}
            }

          _ ->
            %{env | status: 404, body: "NotFound"}
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

  test "file not found", %{client: client} do
    assert {:error, %{status: 404}} = download(client, "http://example.com/nope")
  end

  test "dynamic URL", %{client: client} do
    assert {:ok, file} = download(client, "http://example.com/u/91372?v=3&s=460")
    assert file.name == "91372.png"
  end
end
