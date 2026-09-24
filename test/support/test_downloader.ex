defmodule Bow.TestDownloader do
  @moduledoc false
  @behaviour Bow.Downloader

  @file_cat "test/files/cat.jpg"
  @file_bear "test/files/bear.png"

  @impl true
  def get(url, path, _opts) do
    case url do
      "http://example.com/cat.png" -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com/kitten.png" -> redirect("http://example.com/cat.png")
      "http://example.com/relative/kitten.png" -> redirect("../cat.png")
      "http://example.com/loop.png" -> redirect("http://example.com/loop.png")
      "http://example.com/notype.png" -> ok(path, @file_cat, [])
      "http://example.com/noext" -> ok(path, @file_cat, [])
      "http://example.com/u" <> _ -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com" -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com/dog.jpg" -> ok(path, @file_cat, [{"content-type", "example/dog/nope"}])
      "http://example.com/.weird-path" -> ok(path, @file_cat, [{"content-type", "image/png"}])
      "http://example.com/bear.png" -> ok(path, @file_bear, [{"content-type", "image/png"}])
      "http://example.com/broken" -> {:error, :econnrefused}
      _ -> {:ok, 404, []}
    end
  end

  defp ok(path, file, headers) do
    File.cp!(file, path)
    {:ok, 200, headers}
  end

  defp redirect(location), do: {:ok, 301, [{"location", location}]}
end
