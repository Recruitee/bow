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
      conn
      |> put_resp_header("location", "/cat.jpg")
      |> send_resp(302, "")
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
    assert {:ok, 200, headers} = Httpc.get(base_url <> "/cat.jpg", path, [])
    assert {"content-type", "image/jpeg"} in headers
    assert File.read!(path) == File.read!(@file_cat)
  end

  test "streams big body to file", %{base_url: base_url, path: path} do
    assert {:ok, 200, _headers} = Httpc.get(base_url <> "/big", path, [])
    assert File.stat!(path).size == @big_size
  end

  test "does not follow redirects", %{base_url: base_url, path: path} do
    assert {:ok, 302, headers} = Httpc.get(base_url <> "/redirect", path, [])
    assert {"location", "/cat.jpg"} in headers
    assert File.read!(path) == ""
  end

  test "returns status of failed request", %{base_url: base_url, path: path} do
    assert {:ok, 404, _headers} = Httpc.get(base_url <> "/nope", path, [])
    assert File.read!(path) == ""
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
    assert {:ok, 200, _headers} = Httpc.get(base_url <> "/headers", path, [])
    assert File.read!(path) =~ "user-agent: bow"
  end

  test "custom headers", %{base_url: base_url, path: path} do
    headers = [{"User-Agent", "my-app"}, {"x-token", "secret"}]
    assert {:ok, 200, _headers} = Httpc.get(base_url <> "/headers", path, headers: headers)

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
    assert {:ok, 200, _headers} = Httpc.get(base_url <> "/cat.jpg", path, max_size: size)
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
        redirect: false,
        into: File.stream!(path),
        headers: Keyword.get(opts, :headers, [])
      ]

      case Req.get(url, req_opts) do
        {:ok, %{status: status, headers: headers}} ->
          {:ok, status, for({name, values} <- headers, value <- values, do: {name, value})}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  test "Req downloader example", %{base_url: base_url} do
    assert {:ok, file} = Bow.Download.download(base_url <> "/redirect", downloader: ReqDownloader)
    assert file.name == "cat.jpg"
    assert File.read!(file.path) == File.read!(@file_cat)
  end
end
