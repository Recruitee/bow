defmodule Bow.Download do
  @doc """
  Download file from given URL

  The file name is taken from the final URL returned by the downloader (after redirects),
  or the requested URL, with extension based on the `content-type` header.

  > #### Untrusted URLs {: .warning}
  >
  > When the URL comes from users (e.g. `remote_avatar_url` params), it can point to
  > internal services, like `http://169.254.169.254/` cloud metadata endpoint (SSRF).
  > Validate the URL before downloading it and set `:max_size`.

  Options:
  - `:downloader` - module implementing `Bow.Downloader`, defaults to `:downloader` config
    or `Bow.Downloader.Httpc`
  - `:headers` - request headers as a list of `{name, value}` tuples
  - `:max_size` - maximum file size in bytes. The downloader should stop the download when it's
    exceeded, Bow checks the downloaded file size as well. Returns `{:error, :max_size_exceeded}`.
  - `:timeout` - download timeout in milliseconds, see the downloader docs for the default

  Other options (e.g. `:max_redirects`) are passed to the downloader. Redirects are followed
  by the downloader, see `Bow.Downloader.Httpc` for the default behaviour.
  """
  @spec download(url :: String.t(), opts :: keyword) :: {:ok, Bow.t()} | {:error, any}
  def download(url, opts \\ []) do
    {downloader, opts} = Keyword.pop(opts, :downloader, downloader())
    url = encode(url)
    path = Plug.Upload.random_file!("bow-download")

    with {:ok, response} <- downloader.get(url, path, opts),
         :ok <- check_size(path, opts[:max_size]) do
      {:ok, Bow.new(name: name(response[:url] || url, response.headers), path: path)}
    else
      {:error, reason} ->
        File.rm(path)
        {:error, reason}
    end
  end

  defp downloader, do: Application.get_env(:bow, :downloader, Bow.Downloader.Httpc)

  defp check_size(_path, nil), do: :ok

  defp check_size(path, max_size) do
    if File.stat!(path).size > max_size, do: {:error, :max_size_exceeded}, else: :ok
  end

  defp name(url, headers) do
    base =
      case URI.parse(url) do
        %{path: path} when not is_nil(path) -> Path.basename(path)
        _ -> ""
      end

    with {_, content_type} <- List.keyfind(headers, "content-type", 0),
         [ext | _] <- MIME.extensions(content_type) do
      rootname(base) <> "." <> ext
    else
      _ -> base
    end
  end

  # If path name is malformed, for example looks like this: ".some-data",
  # we won't be able to extract it and we will treat the name
  # as file extension instead.
  #
  # To handle all kind of problems we simply fallback to auto-generated
  # name if we cannot read it properly.
  defp rootname(base) do
    case Path.rootname(base) do
      "" -> 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
      name -> name
    end
  end

  defp encode(url), do: url |> URI.encode() |> String.replace(~r/%25([0-9a-f]{2})/i, "%\\g{1}")
  # based on: https://stackoverflow.com/questions/31825687/how-to-avoid-double-encoding-uri
end
