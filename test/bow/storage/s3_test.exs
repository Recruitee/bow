defmodule Bow.Storage.S3Test do
  use ExUnit.Case

  @moduletag :s3

  alias Bow.Storage.S3

  @empty_file "test/files/empty-file.txt"
  @cat_file "test/files/cat.jpg"

  setup do
    S3.delete("mydir", "cat.jpg", [])
    :ok
  end

  test "store & load file" do
    assert :ok = S3.store(@cat_file, "mydir", "cat.jpg", [])
    assert {:ok, path} = S3.load("mydir", "cat.jpg", [])
    assert File.read!(path) == File.read!(@cat_file)
  end

  test "store & load empty file" do
    assert :ok = S3.store(@empty_file, "mydir", "empty-file.txt", [])
    assert {:ok, path} = S3.load("mydir", "empty-file.txt", [])
    assert File.read!(path) == File.read!(@empty_file)
  end

  test "store as private" do
    assert :ok = S3.store(@cat_file, "mydir", "cat.jpg", acl: :private)
    assert {:ok, path} = S3.load("mydir", "cat.jpg", [])
    assert File.read!(path) == File.read!(@cat_file)
  end

  test "load non-existing file" do
    assert {:error, _} = S3.load("mydir", "nope.png", [])
  end

  test "delete file" do
    assert :ok = S3.store(@cat_file, "mydir", "cat.jpg", [])
    assert :ok = S3.delete("mydir", "cat.jpg", [])
    assert {:error, _} = S3.load("mydir", "cat.jpg", [])
  end

  test "copy file" do
    assert :ok = S3.store(@cat_file, "mydir", "cat.jpg", [])
    assert :ok = S3.copy("mydir", "cat.jpg", "mydir", "kitten.jpg", [])

    assert {:ok, path} = S3.load("mydir", "cat.jpg", [])
    assert File.read!(path) == File.read!(@cat_file)

    assert {:ok, path} = S3.load("mydir", "kitten.jpg", [])
    assert File.read!(path) == File.read!(@cat_file)
  end

  test "unsigned url" do
    url = S3.url("mydir", "cat.jpg", [])
    assert url == "http://test-bucket.localhost/mydir/cat.jpg"
  end

  test "signed url" do
    url = S3.url("mydir", "cat.jpg", signed: true)
    assert "http://test-bucket.localhost:4567/mydir/cat.jpg" <> _ = url
    assert String.contains?(url, "X-Amz-Signature")
  end
end
