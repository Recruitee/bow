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
        def get(url, path, opts) do
          req_opts = [redirect: false, into: File.stream!(path), headers: Keyword.get(opts, :headers, [])]

          case Req.get(url, req_opts) do
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
  - `opts` - options given to `Bow.Download.download/2`, the downloader should support:
    - `:headers` - request headers as a list of `{name, value}` tuples
    - `:max_size` - maximum body size in bytes, stop the download and return
      `{:error, :max_size_exceeded}` when it's exceeded
    - `:timeout` - total download time in milliseconds

  Must not follow redirects, `Bow.Download` takes care of them and calls the downloader again
  with the next URL. Options may differ between calls, e.g. credentials in `:headers` are removed
  on redirect to a different origin, so always use the given `opts` instead of static configuration.

  Must return the response status and headers with lowercase names.
  """
  @callback get(url :: String.t(), path :: Path.t(), opts :: keyword) ::
              {:ok, status :: pos_integer, headers} | {:error, any}
end
