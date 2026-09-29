defmodule Bow.Download do
  @max_redirects 5
  @redirect_statuses [301, 302, 303, 307, 308]

  # Headers filtering on redirect, per RFC 9110 section 15.4 (same lists as Tesla.Middleware.FollowRedirects).
  # Hop-by-hop and conditional request headers do not carry over to a new request.
  @always_strip ~w(connection keep-alive proxy-connection te trailer transfer-encoding upgrade
                   if-match if-modified-since if-none-match if-range if-unmodified-since)
  # Credentials and origin bound headers must not leak to a different origin.
  @cross_origin_strip ~w(authorization cookie host origin proxy-authorization referer)

  @doc """
  Download file from given URL

  The file name is taken from the URL (after following redirects)
  with extension based on the `content-type` header.

  > #### Untrusted URLs {: .warning}
  >
  > When the URL comes from users (e.g. `remote_avatar_url` params), it can point to
  > internal services, like `http://169.254.169.254/` cloud metadata endpoint (SSRF).
  > Validate the URL before downloading it and set `:max_size`.

  Options:
  - `:downloader` - module implementing `Bow.Downloader`, defaults to `:downloader` config
    or `Bow.Downloader.Httpc`
  - `:max_redirects` - maximum number of redirects to follow, defaults to `#{@max_redirects}`
  - `:headers` - request headers as a list of `{name, value}` tuples. On redirect to a different
    origin (scheme, host or port) credentials like `authorization` and `cookie` are removed.
  - `:max_size` - maximum file size in bytes. The downloader should stop the download when it's
    exceeded, Bow checks the downloaded file size as well. Returns `{:error, :max_size_exceeded}`.
  - `:timeout` - download timeout in milliseconds, see the downloader docs for the default

  Other options are passed to the downloader.
  """
  @spec download(url :: String.t(), opts :: keyword) :: {:ok, Bow.t()} | {:error, any}
  def download(url, opts \\ []) do
    {downloader, opts} = Keyword.pop(opts, :downloader, downloader())
    {max_redirects, opts} = Keyword.pop(opts, :max_redirects, @max_redirects)
    path = Plug.Upload.random_file!("bow-download")

    with {:ok, url, headers} <- get(downloader, encode(url), path, opts, max_redirects),
         :ok <- check_size(path, opts[:max_size]) do
      {:ok, Bow.new(name: name(url, headers), path: path)}
    else
      {:error, reason} ->
        File.rm(path)
        {:error, reason}
    end
  end

  defp downloader, do: Application.get_env(:bow, :downloader, Bow.Downloader.Httpc)

  defp get(downloader, url, path, opts, redirects_left) do
    case downloader.get(url, path, opts) do
      {:ok, 200, headers} ->
        {:ok, url, headers}

      {:ok, status, _headers} when status in @redirect_statuses and redirects_left == 0 ->
        {:error, :too_many_redirects}

      {:ok, status, headers} when status in @redirect_statuses ->
        follow_redirect(downloader, url, path, opts, redirects_left, status, headers)

      {:ok, status, headers} ->
        {:error, %{status: status, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp follow_redirect(downloader, url, path, opts, redirects_left, status, headers) do
    with {_, location} <- List.keyfind(headers, "location", 0) do
      next_url = url |> URI.merge(location) |> to_string()
      opts = Keyword.update(opts, :headers, [], &filter_headers(&1, url, next_url))
      get(downloader, next_url, path, opts, redirects_left - 1)
    else
      nil -> {:error, %{status: status, headers: headers}}
    end
  end

  defp filter_headers(headers, url, next_url) do
    drop =
      if cross_origin?(url, next_url),
        do: @always_strip ++ @cross_origin_strip,
        else: @always_strip

    Enum.reject(headers, fn {name, _value} -> String.downcase(to_string(name)) in drop end)
  end

  defp cross_origin?(url, next_url), do: origin(url) != origin(next_url)

  defp origin(url) do
    uri = URI.parse(url)
    {uri.scheme, uri.host && String.downcase(uri.host), uri.port}
  end

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
