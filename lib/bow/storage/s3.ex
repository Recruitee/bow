defmodule Bow.Storage.S3 do
  @behaviour Bow.Storage

  @moduledoc """
  Amazon S3 storage adapter

  ## Configuration

      config :recruitee, :bow,
        storage:  Bow.Storage.S3

      config :ex_aws,
        bucket:   "my-s3-bucket",
        access_key_id:      "aws-key",
        secret_access_key:  "aws-secret",
        region:             "eu-central-1"

  """

  defp bucket, do: Application.get_env(:ex_aws, :bucket)
  defp assets_host, do: Application.get_env(:bow, :assets_host, "https://#{bucket()}.s3.amazonaws.com")
  defp expire_in,   do: Application.get_env(:bow, :expire_in, 24 * 60 * 60)

  def store(path, dir, name, opts) do
    key   = Path.join(dir, name)
    data  = File.read!(path)

    with {:ok, _} <- ExAws.S3.put_object(bucket(), key, data, opts), do: :ok
  end

  def load(dir, name, opts) do
    key   = Path.join(dir, name)
    path  = Plug.Upload.random_file("bow-s3")

    with  {:ok, %{body: data}} <- ExAws.S3.get_object(bucket(), key, opts),
          :ok <- File.write(path, data, [:binary]) do
      {:ok, path}
    end
  end

  def delete(dir, name, opts) do
    key = Path.join(dir, name)
    ExAws.S3.delete_object(bucket(), key, opts)
  end

  def url(dir, name, opts) do
    key = Path.join(dir, name)
    case Map.pop(opts, :signed) do
      {true, opts}  -> signed_url(key, opts)
      _             -> unsigned_url(key)
    end
  end

  defp signed_url(key, opts) do
    opts =
      opts
      |> Keyword.put_new(:expire_in, expire_in())
      |> Keyword.put_new(:virtual_host, true)

    with {:ok, url} <- ExAws.S3.presigned_url(:get, bucket(), key, opts), do: url
  end

  defp unsigned_url(key) do
    Path.join(assets_host(), key)
  end
end
