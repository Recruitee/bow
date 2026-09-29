defmodule Bow.Downloader.Httpc do
  @moduledoc """
  Default `Bow.Downloader` based on Erlang `:httpc`

  The response body is streamed directly to the file.
  HTTPS certificates are verified using the operating system CA store.
  The request runs in a separate process, so late `:httpc` messages
  (e.g. after a timeout) never reach the calling process.

  Options:
  - `:timeout` - total download time in milliseconds (not the idle time between chunks),
    defaults to `30_000`. Returns `{:error, :timeout}` when exceeded.
  - `:headers` - request headers as a list of `{name, value}` tuples,
    `user-agent` defaults to `"bow"`
  - `:max_size` - maximum body size in bytes. The download is aborted as soon as
    `content-length` or the received data exceeds it. Returns `{:error, :max_size_exceeded}`.
  """

  @behaviour Bow.Downloader

  @default_timeout 30_000
  @default_headers [{"user-agent", "bow"}]
  # request/4 stops itself at the deadline, this only covers the cleanup
  @shutdown_margin 1_000

  @impl true
  def get(url, path, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    task = Task.async(fn -> request(url, path, opts, timeout) end)

    case Task.yield(task, timeout + @shutdown_margin) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end

  defp request(url, path, opts, timeout) do
    state = %{
      path: path,
      max_size: opts[:max_size],
      deadline: System.monotonic_time(:millisecond) + timeout
    }

    request = {String.to_charlist(url), request_headers(opts)}

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
      {:ok, ref} -> receive_response(ref, state)
      {:error, reason} -> {:error, reason}
    end
  end

  # :httpc streams only 200 and 206 responses, others are received at once
  defp receive_response(ref, state) do
    receive do
      {:http, {^ref, :stream_start, headers}} ->
        save_stream(ref, normalize(headers), state)

      {:http, {^ref, {{_version, status, _reason}, headers, body}}} ->
        save_body(status, normalize(headers), body, state)

      {:http, {^ref, {:error, reason}}} ->
        {:error, reason}
    after
      remaining(state) -> cancel(ref, :timeout)
    end
  end

  defp save_stream(ref, headers, state) do
    with :ok <- check_content_length(headers, state.max_size),
         {:ok, :ok} <- File.open(state.path, [:write, :binary], &stream_body(ref, &1, 0, state)) do
      # Range header is never sent, so a streamed response can't be 206
      {:ok, 200, headers}
    else
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> cancel(ref, reason)
    end
  end

  defp save_body(status, headers, body, state) when status in 200..299 do
    with :ok <- check_size(byte_size(body), state.max_size),
         :ok <- File.write(state.path, body) do
      {:ok, status, headers}
    end
  end

  defp save_body(status, headers, _body, _state), do: {:ok, status, headers}

  defp stream_body(ref, file, size, state) do
    receive do
      {:http, {^ref, :stream, chunk}} ->
        write_chunk(ref, file, size + byte_size(chunk), chunk, state)

      {:http, {^ref, :stream_end, _headers}} ->
        :ok

      {:http, {^ref, {:error, reason}}} ->
        {:error, reason}
    after
      remaining(state) -> cancel(ref, :timeout)
    end
  end

  defp write_chunk(ref, _file, size, _chunk, %{max_size: max_size})
       when is_integer(max_size) and size > max_size do
    cancel(ref, :max_size_exceeded)
  end

  defp write_chunk(ref, file, size, chunk, state) do
    IO.binwrite(file, chunk)
    stream_body(ref, file, size, state)
  end

  defp check_content_length(headers, max_size) do
    with {_, value} <- List.keyfind(headers, "content-length", 0),
         {length, ""} <- Integer.parse(value) do
      check_size(length, max_size)
    else
      _ -> :ok
    end
  end

  defp check_size(size, max_size) when is_integer(max_size) and size > max_size,
    do: {:error, :max_size_exceeded}

  defp check_size(_size, _max_size), do: :ok

  defp remaining(state), do: max(state.deadline - System.monotonic_time(:millisecond), 0)

  defp cancel(ref, reason) do
    :httpc.cancel_request(ref)
    {:error, reason}
  end

  defp request_headers(opts) do
    headers = Keyword.get(opts, :headers, [])
    names = MapSet.new(headers, fn {name, _value} -> String.downcase(to_string(name)) end)
    defaults = Enum.reject(@default_headers, fn {name, _value} -> name in names end)

    for {name, value} <- defaults ++ headers do
      {to_charlist(name), to_charlist(value)}
    end
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
