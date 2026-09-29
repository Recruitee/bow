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
          req_opts = [
            url: url,
            into: File.stream!(path),
            headers: Keyword.get(opts, :headers, []),
            max_redirects: Keyword.get(opts, :max_redirects, 5)
          ]

          case Req.run(req_opts) do
            {req, %Req.Response{status: status} = resp} when status in 200..299 ->
              {:ok, %{url: URI.to_string(req.url), headers: headers(resp)}}

            {_req, %Req.Response{status: status} = resp} ->
              {:error, %{status: status, headers: headers(resp)}}

            {_req, exception} ->
              {:error, exception}
          end
        end

        defp headers(resp) do
          for {name, values} <- resp.headers, value <- values, do: {name, value}
        end
      end

  Req follows redirects, but on redirect to a different origin it removes only
  the `authorization` header, other credentials like `cookie` are sent as they are.
  """

  @type headers :: [{name :: String.t(), value :: String.t()}]

  @typedoc """
  Successful response

  - `:url` - final URL after redirects, used for the file name. When missing,
    the requested URL is used.
  - `:headers` - response headers with lowercase names
  """
  @type response :: %{required(:headers) => headers, optional(:url) => String.t()}

  @doc """
  Download the file with a GET request

  Arguments:
  - `url` - URL to request
  - `path` - path the response body must be written to when the status is 2xx
  - `opts` - options given to `Bow.Download.download/2`, the downloader should support:
    - `:headers` - request headers as a list of `{name, value}` tuples
    - `:max_size` - maximum body size in bytes, stop the download and return
      `{:error, :max_size_exceeded}` when it's exceeded
    - `:timeout` - total download time in milliseconds

  The downloader is responsible for following redirects (and supporting `:max_redirects`
  if it makes sense for it). On redirect to a different origin (scheme, host or port) make sure
  credentials like `authorization` and `cookie` from `:headers` do not leak to the new host.

  Returns `{:ok, response}` for 2xx responses and `{:error, %{status: status, headers: headers}}`
  for other statuses.
  """
  @callback get(url :: String.t(), path :: Path.t(), opts :: keyword) ::
              {:ok, response} | {:error, any}
end
