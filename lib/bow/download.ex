defmodule Bow.Download do
  @max_redirects 5
  @redirect_statuses [301, 302, 303, 307, 308]

  @doc """
  Download file from given URL

  The file name is taken from the URL (after following redirects)
  with extension based on the `content-type` header.

  Options:
  - `:downloader` - module implementing `Bow.Downloader`, defaults to `:downloader` config
    or `Bow.Downloader.Httpc`
  - `:max_redirects` - maximum number of redirects to follow, defaults to `#{@max_redirects}`

  Other options are passed to the downloader.
  """
  @spec download(url :: String.t(), opts :: keyword) :: {:ok, Bow.t()} | {:error, any}
  def download(url, opts \\ []) do
    {downloader, opts} = Keyword.pop(opts, :downloader, downloader())
    {max_redirects, opts} = Keyword.pop(opts, :max_redirects, @max_redirects)
    path = Plug.Upload.random_file!("bow-download")

    with {:ok, url, headers} <- get(downloader, encode(url), path, opts, max_redirects) do
      {:ok, Bow.new(name: name(url, headers), path: path)}
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
      get(downloader, next_url, path, opts, redirects_left - 1)
    else
      nil -> {:error, %{status: status, headers: headers}}
    end
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
