defmodule Bow.Downloader.HttpcTest do
  use ExUnit.Case

  alias Bow.Downloader.Httpc

  @file_cat "test/files/cat.jpg"
  @big_size 3 * 1024 * 1024

  defmodule Router do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    get "/cat.jpg" do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> send_file(200, "test/files/cat.jpg")
    end

    get "/big" do
      conn = send_chunked(conn, 200)
      chunk = :binary.copy("a", 1024 * 1024)
      Enum.reduce(1..3, conn, fn _, conn -> elem(chunk(conn, chunk), 1) end)
    end

    get "/redirect" do
      redirect(conn, 302, "/cat.jpg")
    end

    get "/relative/redirect" do
      redirect(conn, 301, "../cat.jpg")
    end

    get "/loop" do
      redirect(conn, 307, "/loop")
    end

    get "/slow-loop" do
      Process.sleep(150)
      redirect(conn, 302, "/slow-loop")
    end

    get "/no-location" do
      send_resp(conn, 302, "")
    end

    get "/to-headers" do
      redirect(conn, 302, "/headers")
    end

    # same port, different host, so a different origin
    get "/to-other-origin" do
      redirect(conn, 302, "http://localhost:#{conn.port}/headers")
    end

    get "/slow" do
      Process.sleep(1000)
      send_resp(conn, 200, "late")
    end

    # sends a chunk every 100ms for 1s, so it's never idle longer than the timeout
    get "/drip" do
      conn = send_chunked(conn, 200)

      # stop when the client disconnects after its timeout
      Enum.reduce_while(1..10, conn, fn _, conn ->
        Process.sleep(100)

        case chunk(conn, ".") do
          {:ok, conn} -> {:cont, conn}
          {:error, :closed} -> {:halt, conn}
        end
      end)
    end

    get "/headers" do
      body =
        Enum.map_join(conn.req_headers, "\n", fn {name, value} -> "#{name}: #{value}" end)

      send_resp(conn, 200, body)
    end

    match _ do
      send_resp(conn, 404, "nope")
    end

    defp redirect(conn, status, location) do
      conn
      |> put_resp_header("location", location)
      |> send_resp(status, "")
    end
  end

  setup_all do
    {:ok, server} = Bandit.start_link(plug: Router, ip: :loopback, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    %{base_url: "http://127.0.0.1:#{port}"}
  end

  setup do
    %{path: Plug.Upload.random_file!("httpc-test")}
  end

  test "writes body to file", %{base_url: base_url, path: path} do
    assert {:ok, %{headers: headers}} = Httpc.get(base_url <> "/cat.jpg", path, [])
    assert {"content-type", "image/jpeg"} in headers
    assert File.read!(path) == File.read!(@file_cat)
  end

  test "streams big body to file", %{base_url: base_url, path: path} do
    assert {:ok, _response} = Httpc.get(base_url <> "/big", path, [])
    assert File.stat!(path).size == @big_size
  end

  test "returns error with status of failed request", %{base_url: base_url, path: path} do
    assert {:error, %{status: 404, headers: _}} = Httpc.get(base_url <> "/nope", path, [])
    assert File.read!(path) == ""
  end

  describe "redirects" do
    @headers [
      {"Authorization", "Bearer secret"},
      {"cookie", "session=1"},
      {"If-None-Match", "etag"},
      {"accept", "image/*"}
    ]

    test "are followed", %{base_url: base_url, path: path} do
      assert {:ok, %{url: url}} = Httpc.get(base_url <> "/redirect", path, [])
      assert url == base_url <> "/cat.jpg"
      assert File.read!(path) == File.read!(@file_cat)
    end

    test "relative location", %{base_url: base_url, path: path} do
      assert {:ok, %{url: url}} = Httpc.get(base_url <> "/relative/redirect", path, [])
      assert url == base_url <> "/cat.jpg"
    end

    test "too many redirects", %{base_url: base_url, path: path} do
      assert {:error, :too_many_redirects} = Httpc.get(base_url <> "/loop", path, [])
    end

    test "max redirects option", %{base_url: base_url, path: path} do
      assert {:error, :too_many_redirects} =
               Httpc.get(base_url <> "/redirect", path, max_redirects: 0)
    end

    test "without location", %{base_url: base_url, path: path} do
      assert {:error, %{status: 302}} = Httpc.get(base_url <> "/no-location", path, [])
    end

    test "timeout covers all redirects", %{base_url: base_url, path: path} do
      assert {:error, :timeout} =
               Httpc.get(base_url <> "/slow-loop", path, timeout: 400, max_redirects: 10)
    end

    test "keep credentials on the same origin", %{base_url: base_url, path: path} do
      assert {:ok, _response} = Httpc.get(base_url <> "/to-headers", path, headers: @headers)

      body = File.read!(path)
      assert body =~ "authorization: Bearer secret"
      assert body =~ "cookie: session=1"
      assert body =~ "accept: image/*"
      refute body =~ "if-none-match"
    end

    test "remove credentials on a different origin", %{base_url: base_url, path: path} do
      assert {:ok, %{url: "http://localhost:" <> _}} =
               Httpc.get(base_url <> "/to-other-origin", path, headers: @headers)

      body = File.read!(path)
      refute body =~ "authorization"
      refute body =~ "cookie"
      refute body =~ "if-none-match"
      assert body =~ "accept: image/*"
    end
  end

  test "timeout", %{base_url: base_url, path: path} do
    assert {:error, :timeout} = Httpc.get(base_url <> "/slow", path, timeout: 100)
  end

  test "timeout is the total download time", %{base_url: base_url, path: path} do
    started_at = System.monotonic_time(:millisecond)
    assert {:error, :timeout} = Httpc.get(base_url <> "/drip", path, timeout: 300)
    assert System.monotonic_time(:millisecond) - started_at < 800
  end

  test "late messages do not reach the caller", %{base_url: base_url, path: path} do
    assert {:error, :timeout} = Httpc.get(base_url <> "/drip", path, timeout: 150)
    assert {:error, :timeout} = Httpc.get(base_url <> "/slow", path, timeout: 100)
    refute_receive {:http, _}, 1_500
  end

  test "default user agent", %{base_url: base_url, path: path} do
    assert {:ok, _response} = Httpc.get(base_url <> "/headers", path, [])
    assert File.read!(path) =~ "user-agent: bow"
  end

  test "custom headers", %{base_url: base_url, path: path} do
    headers = [{"User-Agent", "my-app"}, {"x-token", "secret"}]
    assert {:ok, _response} = Httpc.get(base_url <> "/headers", path, headers: headers)

    body = File.read!(path)
    assert body =~ "user-agent: my-app"
    refute body =~ "user-agent: bow"
    assert body =~ "x-token: secret"
  end

  test "max size exceeded by content-length", %{base_url: base_url, path: path} do
    assert {:error, :max_size_exceeded} = Httpc.get(base_url <> "/cat.jpg", path, max_size: 100)
    assert File.read!(path) == ""
  end

  test "max size exceeded while streaming", %{base_url: base_url, path: path} do
    assert {:error, :max_size_exceeded} =
             Httpc.get(base_url <> "/big", path, max_size: 1024 * 1024)

    assert File.stat!(path).size <= 1024 * 1024
  end

  test "max size not exceeded", %{base_url: base_url, path: path} do
    size = File.stat!(@file_cat).size
    assert {:ok, _response} = Httpc.get(base_url <> "/cat.jpg", path, max_size: size)
  end

  test "connection error", %{path: path} do
    assert {:error, {:failed_connect, _}} = Httpc.get("http://127.0.0.1:1/cat.jpg", path, [])
  end

  test "default downloader of Bow.Download", %{base_url: base_url} do
    assert {:ok, file} = Bow.Download.download(base_url <> "/redirect")
    assert file.name == "cat.jpg"
    assert File.read!(file.path) == File.read!(@file_cat)
  end

  defmodule ReqDownloader do
    # example from Bow.Downloader docs
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

  test "Req downloader example", %{base_url: base_url} do
    assert {:ok, file} = Bow.Download.download(base_url <> "/redirect", downloader: ReqDownloader)
    assert file.name == "cat.jpg"
    assert File.read!(file.path) == File.read!(@file_cat)
  end
end
