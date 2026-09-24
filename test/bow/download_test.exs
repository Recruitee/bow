defmodule Bow.DownloadTest do
  use ExUnit.Case

  @file_cat "test/files/cat.jpg"

  defp download(url, opts \\ []) do
    Bow.Download.download(url, [downloader: Bow.TestDownloader] ++ opts)
  end

  test "regular file" do
    assert {:ok, file} = download("http://example.com/cat.png")
    assert file.name == "cat.png"
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file with redirect" do
    assert {:ok, file} = download("http://example.com/kitten.png")
    assert file.name == "cat.png"
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file with relative redirect" do
    assert {:ok, file} = download("http://example.com/relative/kitten.png")
    assert file.name == "cat.png"
  end

  test "too many redirects" do
    assert {:error, :too_many_redirects} = download("http://example.com/loop.png")
  end

  test "max redirects option" do
    assert {:error, :too_many_redirects} =
             download("http://example.com/kitten.png", max_redirects: 0)
  end

  test "file without content type" do
    assert {:ok, file} = download("http://example.com/notype.png")
    assert file.name == "notype.png"
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file without extension" do
    assert {:ok, file} = download("http://example.com/noext")
    assert file.name == "noext"
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file with invalid content type" do
    assert {:ok, file} = download("http://example.com/dog.jpg")
    assert file.name == "dog.jpg"
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "url with path starting with dot" do
    assert {:ok, file} = download("http://example.com/.weird-path")
    assert Regex.match?(~r/.+\.png/, file.name)
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "file not found" do
    assert {:error, %{status: 404}} = download("http://example.com/nope")
  end

  test "downloader error" do
    assert {:error, :econnrefused} = download("http://example.com/broken")
  end

  test "without file path" do
    assert {:ok, file} = download("http://example.com")
    assert file.name =~ ~r/^[0-9a-f]{32}\.png$/
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  test "dynamic URL" do
    assert {:ok, file} = download("http://example.com/u/91372?v=3&s=460")
    assert file.name == "91372.png"
  end

  test "downloader from config" do
    Application.put_env(:bow, :downloader, Bow.TestDownloader)
    on_exit(fn -> Application.delete_env(:bow, :downloader) end)

    assert {:ok, %Bow{name: "cat.png"}} = Bow.Download.download("http://example.com/cat.png")
  end
end
