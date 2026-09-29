defmodule Bow.TestDownloader do
  @moduledoc false
  @behaviour Bow.Downloader

  @file_cat "test/files/cat.jpg"
  @file_bear "test/files/bear.png"

  @impl true
  def get(url, path, opts) do
    send(self(), {:downloader_get, url, path, opts})

    case url do
      "http://example.com/cat.png" -> ok(path, @file_cat, [{"content-type", "image/png"}])
      # redirected to http://example.com/cat.png
      "http://example.com/kitten.png" -> ok(path, @file_cat, "http://example.com/cat.png")
      "http://example.com/notype.png" -> ok(path, @file_cat, [])
      "http://example.com/noext" -> ok(path, @file_cat, [])
      "http://example.com/u" <> _ -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com" -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com/dog.jpg" -> ok(path, @file_cat, [{"content-type", "example/dog/nope"}])
      "http://example.com/.weird-path" -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com/bear.png" -> ok(path, @file_bear, [{"content-type", "image/png"}])
      "http://example.com/broken" -> {:error, :econnrefused}
      _ -> {:error, %{status: 404, headers: []}}
    end
  end

  defp ok(path, file, final_url) when is_binary(final_url) do
    File.cp!(file, path)
    {:ok, %{url: final_url, headers: [{"content-type", "image/png"}]}}
  end

  # without :url, like a downloader that does not know the final URL
  defp ok(path, file, headers) do
    File.cp!(file, path)
    {:ok, %{headers: headers}}
  end
end
