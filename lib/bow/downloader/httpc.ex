defmodule Bow.Downloader.Httpc do
  @moduledoc """
  Default `Bow.Downloader` based on Erlang `:httpc`

  The response body is streamed directly to the file.
  HTTPS certificates are verified using the operating system CA store.

  Options:
  - `:timeout` - request timeout in milliseconds, defaults to `30_000`
  """

  @behaviour Bow.Downloader

  @default_timeout 30_000

  @impl true
  def get(url, path, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    request = {String.to_charlist(url), [{~c"user-agent", ~c"bow"}]}

    http_opts = [
      timeout: timeout,
      connect_timeout: timeout,
      autoredirect: false,
      ssl: ssl_opts()
    ]

    case :httpc.request(:get, request, http_opts,
           sync: false,
           stream: :self,
           body_format: :binary
         ) do
      {:ok, ref} -> receive_response(ref, path, timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  # :httpc streams only 200 and 206 responses, others are received at once
  defp receive_response(ref, path, timeout) do
    receive do
      {:http, {^ref, :stream_start, headers}} ->
        save_stream(ref, path, headers, timeout)

      {:http, {^ref, {{_version, status, _reason}, headers, body}}} ->
        save_body(path, status, headers, body)

      {:http, {^ref, {:error, reason}}} ->
        {:error, reason}
    after
      timeout -> cancel(ref, :timeout)
    end
  end

  defp save_stream(ref, path, headers, timeout) do
    with {:ok, :ok} <- File.open(path, [:write, :binary], &stream_body(ref, &1, timeout)) do
      {:ok, 200, normalize(headers)}
    else
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> cancel(ref, reason)
    end
  end

  defp save_body(path, status, headers, body) when status in 200..299 do
    with :ok <- File.write(path, body) do
      {:ok, status, normalize(headers)}
    end
  end

  defp save_body(_path, status, headers, _body), do: {:ok, status, normalize(headers)}

  defp stream_body(ref, file, timeout) do
    receive do
      {:http, {^ref, :stream, chunk}} ->
        IO.binwrite(file, chunk)
        stream_body(ref, file, timeout)

      {:http, {^ref, :stream_end, _headers}} ->
        :ok

      {:http, {^ref, {:error, reason}}} ->
        {:error, reason}
    after
      timeout -> cancel(ref, :timeout)
    end
  end

  defp cancel(ref, reason) do
    :httpc.cancel_request(ref)
    {:error, reason}
  end

  defp normalize(headers) do
    for {name, value} <- headers do
      {name |> to_string() |> String.downcase(), to_string(value)}
    end
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
