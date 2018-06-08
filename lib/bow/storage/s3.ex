defmodule Bow.Storage.S3 do
  @behaviour Bow.Storage

  @moduledoc """
  Amazon S3 storage adapter

  ## Configuration

      config :recruitee, :bow,
        storage:  Bow.Storage.S3

      config :ex_aws,
        access_key_id:      "aws-key",
        secret_access_key:  "aws-secret",
        region:             "eu-central-1"

      config :ex_aws, :s3,
        bucket: "my-bucket"

  """

  defp s3config, do: ExAws.Config.new(:s3)

  defp bucket do
    case s3config() do
      %{bucket: bucket} -> bucket
      _ -> raise ArgumentError, message: "Missing :ex_aws, :s3, bucket: \"...\" configuration"
    end
  end

  defp assets_host do
    case Application.get_env(:bow, :assets_host) do
      nil ->
        %{bucket: bucket, host: host} = conf = s3config()
        scheme = Map.get(conf, :scheme, "https://")
        "#{scheme}#{bucket}.#{host}"
      host ->
        host
    end
  end

  defp expire_in, do: Application.get_env(:bow, :expire_in, 24 * 60 * 60)

  @impl true
  def store(path, dir, name, opts) do
    if File.stat!(path).size == 0 do
      # Currently stream_file() doesn't work with empty files
      # ( https://github.com/ex-aws/ex_aws_s3/issues/3 ),
      # so let's do it in the more simple way in that case.
      ExAws.S3.put_object(bucket(), Path.join(dir, name), "")
      |> ExAws.request()
      |> case do
        {:ok, %{status_code: 200}} -> :ok
        error -> error
      end
    else
      path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket(), Path.join(dir, name), opts)
      |> ExAws.request()
      |> case do
        {:ok, %{status_code: 200}} -> :ok
        error -> error
      end
    end
  rescue
    ex in ExAws.Error -> {:error, ex}
  end

  @impl true
  def load(dir, name, opts) do
    path = Plug.Upload.random_file!("bow-s3")

    bucket()
    |> ExAws.S3.download_file(Path.join(dir, name), path, opts)
    |> ExAws.request()
    |> case do
      {:ok, :done} -> {:ok, path}
      error -> error
    end
  rescue
    ex in ExAws.Error -> {:error, ex}
  end

  @impl true
  def delete(dir, name, opts) do
    bucket()
    |> ExAws.S3.delete_object(Path.join(dir, name), opts)
    |> ExAws.request()
    |> case do
      {:ok, %{status_code: 204}} -> :ok
      error -> error
    end
  rescue
    ex in ExAws.Error -> {:error, ex}
  end

  @impl true
  def copy(src_dir, src_name, dst_dir, dst_name, opts) do
    src_path = Path.join(src_dir, src_name)
    dst_path = Path.join(dst_dir, dst_name)

    bucket()
    |> ExAws.S3.put_object_copy(dst_path, bucket(), src_path, opts)
    |> ExAws.request()
    |> case do
      {:ok, %{status_code: 200}} -> :ok
      error -> error
    end
  rescue
    ex in ExAws.Error -> {:error, ex}
  end

  @impl true
  def url(dir, name, opts) do
    key = Path.join(dir, name)
    case Keyword.pop(opts, :signed) do
      {true, opts}  -> signed_url(key, opts)
      _             -> unsigned_url(key)
    end
  end

  defp signed_url(key, opts) do
    opts =
      opts
      |> Keyword.put_new(:expire_in, expire_in())
      |> Keyword.put_new(:virtual_host, true)

    {:ok, url} = ExAws.S3.presigned_url(ExAws.Config.new(:s3), :get, bucket(), key, opts)
    url
  end

  defp unsigned_url(key) do
    Path.join(assets_host(), key)
  end
end
