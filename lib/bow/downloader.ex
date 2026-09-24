defmodule Bow.Downloader do
  @moduledoc """
  Behaviour for HTTP clients used by `Bow.Download`

  Bow uses `Bow.Downloader.Httpc` (based on Erlang `:httpc`) by default.
  You can provide your own implementation, e.g. to use a different HTTP client,
  a proxy or to mock requests in tests:

      config :bow, downloader: MyApp.BowDownloader

  The downloader can also be passed per call with the `:downloader` option
  of `Bow.Download.download/2` and `Bow.Ecto.cast_uploads/4`.

  ## Example

  Implementation based on [Req](https://hexdocs.pm/req):

      defmodule MyApp.BowDownloader do
        @behaviour Bow.Downloader

        @impl true
        def get(url, path, _opts) do
          case Req.get(url, redirect: false, into: File.stream!(path)) do
            {:ok, %{status: status, headers: headers}} ->
              {:ok, status, for({name, values} <- headers, value <- values, do: {name, value})}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end
  """

  @type headers :: [{name :: String.t(), value :: String.t()}]

  @doc """
  Make a single GET request

  Arguments:
  - `url` - URL to request
  - `path` - path the response body must be written to when the status is 2xx
  - `opts` - options given to `Bow.Download.download/2`

  Must not follow redirects, `Bow.Download` takes care of them.
  Must return the response status and headers with lowercase names.
  """
  @callback get(url :: String.t(), path :: Path.t(), opts :: keyword) ::
              {:ok, status :: pos_integer, headers} | {:error, any}
end
