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
    def get(url, path, _opts) do
      case Req.get(url, redirect: false, into: File.stream!(path)) do
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
