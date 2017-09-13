defmodule Bow.Download do
  use Tesla

  plug Tesla.Middleware.FollowRedirects

  @doc """
  Download file from given URL
  """
  @spec download(client :: Tesla.Client.t | nil, url :: String.t) :: {:ok, Bow.t} | {:error, any}
  def download(client \\ nil, url) do
    case get(client, URI.encode(url)) do
      %{status: 200, url: url, body: body, headers: headers} ->
        base = url |> URI.parse |> Map.get(:path) |> Path.basename
        name = case Map.fetch(headers, "content-type") do
          {:ok, content_type} ->
            case MIME.extensions(content_type) do
              [ext | _] -> Path.rootname(base) <> "." <> ext
              _         -> base
            end
          :error ->
            base
        end

        path = Plug.Upload.random_file!("bow-download")
        case File.write(path, body) do
          :ok ->
            {:ok, Bow.new(name: name, path: path)}

          {:error, reason} ->
            {:error, reason}
        end
      env ->
        {:error, env}
    end
  rescue
    ex in Tesla.Error ->
      {:error, ex}
  end
end
