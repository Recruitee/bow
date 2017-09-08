defmodule BowTest do
  use ExUnit.Case

  setup do
    Bow.Storage.Local.reset!
    :ok
  end

  defmodule Convert do
    def copy(source, target) do
      with  {:ok, path} <- Plug.Upload.random_file("bow"),
            :ok <- File.cp(source.path, path) do
        {:ok, %{target | path: path}}
      end
    end
  end

  @file_cat     "test/files/cat.jpg"
  @file_bear    "test/files/bear.png"
  @file_roomba  "test/files/roomba.gif"
  @file_report  "test/files/report.pdf"
  @file_cv      "test/files/cv.docx"
  @file_memo    "test/files/memo.txt"

  describe "#new" do
    test "with name" do
      file = Bow.new(name: "cat.jpg")
      assert file.name == "cat.jpg"
      assert file.rootname == "cat"
      assert file.ext == ".jpg"
      assert file.path == nil
    end

    test "with name, no ext" do
      file = Bow.new(name: "README")
      assert file.name == "README"
      assert file.rootname == "README"
      assert file.ext == ""
      assert file.path == nil
    end

    test "create with path" do
      file = Bow.new(path: "path/to/file.png")
      assert file.name == "file.png"
      assert file.rootname == "file"
      assert file.ext == ".png"
      assert file.path == "path/to/file.png"
    end

    test "create with path, no ext" do
      file = Bow.new(path: "path/to/blob")
      assert file.name == "blob"
      assert file.rootname == "blob"
      assert file.ext == ""
      assert file.path == "path/to/blob"
    end
  end

  describe "Minimal uploader" do
    defmodule MinimalUploader do
      use Bow.Uploader

      def store_dir(_) do
        "minimal"
      end
    end

    test "#store" do
      file = MinimalUploader.new(path: @file_cat)
      assert {:ok, _results} = Bow.store(file)
      assert File.exists?("tmp/bow/minimal/cat.jpg")
      assert File.read!(@file_cat) == File.read!("tmp/bow/minimal/cat.jpg")
    end

    test "#load - ok" do
      # store it first
      MinimalUploader.new(path: @file_cat) |> Bow.store()

      # then test loading
      file = MinimalUploader.new(name: "cat.jpg")
      assert {:ok, file} = Bow.load(file)
      assert file.path == "tmp/bow/minimal/cat.jpg"
    end

    test "#load - error" do
      file = MinimalUploader.new(name: "nope.gif")
      assert {:error, _} = Bow.load(file)
    end
  end

  describe "Generate thumbs" do
    defmodule ThumbnailUploader do
      use Bow.Uploader

      def versions(file) do
        case file.ext do
          ".jpg" -> [:original, :thumb]
          ".gif" -> [:thumb]
          _      -> []
        end
      end

      def transform(source, target, :original), do: transform_original(source, target)

      def transform(source, target, :thumb) do
        Convert.copy(source, target)
      end

      def filename(file, :original),  do: file.name
      def filename(file, version),    do: "#{version}_#{file.name}"

      def store_dir(_file) do
        "thumbnail"
      end
    end

    test "upload .jpg and thumb file in correct directory" do
      file = ThumbnailUploader.new(path: @file_cat)
      assert {:ok, _results} = Bow.store(file)

      assert File.exists?("tmp/bow/thumbnail/cat.jpg")
      assert File.exists?("tmp/bow/thumbnail/thumb_cat.jpg")

      assert File.read!(@file_cat) == File.read!("tmp/bow/thumbnail/cat.jpg")
    end

    test "upload .gif but store only thumb" do
      file = ThumbnailUploader.new(path: @file_roomba)
      assert {:ok, _results} = Bow.store(file)

      refute File.exists?("tmp/bow/thumbnail/roomba.gif")
      assert File.exists?("tmp/bow/thumbnail/thumb_roomba.gif")
    end
  end

  describe "Transform pipeline" do
    defmodule PipelineUploader do
      use Bow.Uploader

      def versions(file) do
        case file.ext do
          ".pdf"  -> [:original, :thumb]  # for pdf, store original and make thumb
          ".docx" -> [:original, :pdf]    # for doc, store original and generate pdf
          ".png"  -> [:original, :image_thumb1]
          _       -> []                   # ignore the rest
        end
      end

      # do nothing with original file
      def transform(source, target, :original), do: transform_original(source, target)

      # convert to pdf
      def transform(source, target, :pdf) do
        with {:ok, pdf} <- Convert.copy(source, target) do
          {:ok, pdf, [:thumb]} # and then convert to thumb
        end
      end

      # convert pdf to thumb
      def transform(source, target, :thumb) do
        Convert.copy(source, target)
      end

      def transform(source, target, :image_thumb1) do
        with {:ok, image} <- Convert.copy(source, target) do
          {:ok, image, [:image_thumb2]}
        end
      end

      def transform(source, target, :image_thumb2) do
        with {:ok, image} <- Convert.copy(source, target) do
          {:ok, image, [:image_thumb3]}
        end
      end

      def transform(source, target, :image_thumb3) do
        Convert.copy(source, target)
      end

      # filename must return full filename with extension
      def filename(file, :original),  do: file.name
      def filename(file, :pdf),       do: "#{file.rootname}.pdf"
      def filename(file, :thumb),     do: "thumb_#{file.rootname}.png"
      def filename(file, :image_thumb1), do: "thumb1_#{file.name}"
      def filename(file, :image_thumb2), do: "thumb2_#{file.name}"
      def filename(file, :image_thumb3), do: "thumb3_#{file.name}"

      def store_dir(_file) do
        "pipeline"
      end
    end

    test "upload .pdf and generate thumb image" do
      file = PipelineUploader.new(path: @file_report)
      assert {:ok, results} = Bow.store(file)
      assert results[:original] == :ok
      assert results[:thumb] == :ok
      assert length(results) == 2

      assert File.exists?("tmp/bow/pipeline/report.pdf")
      assert File.exists?("tmp/bow/pipeline/thumb_report.png")
    end

    test "upload .doc, generate pdf and pdf thumb image" do
      file = PipelineUploader.new(path: @file_cv)
      assert {:ok, results} = Bow.store(file)
      assert results[:original] == :ok
      assert results[:pdf] == :ok
      assert results[:thumb] == :ok
      assert length(results) == 3

      assert File.exists?("tmp/bow/pipeline/cv.docx")
      assert File.exists?("tmp/bow/pipeline/cv.pdf")
      assert File.exists?("tmp/bow/pipeline/thumb_cv.png")
    end

    test "upload .png and generate three nested thumbnails" do
      file = PipelineUploader.new(path: @file_bear)
      assert {:ok, results} = Bow.store(file)
      assert results[:original] == :ok
      assert results[:image_thumb1] == :ok
      assert results[:image_thumb2] == :ok
      assert results[:image_thumb3] == :ok
      assert length(results) == 4

      assert File.exists?("tmp/bow/pipeline/bear.png")
      assert File.exists?("tmp/bow/pipeline/thumb1_bear.png")
      assert File.exists?("tmp/bow/pipeline/thumb2_bear.png")
      assert File.exists?("tmp/bow/pipeline/thumb3_bear.png")

      assert PipelineUploader.url(file) == "tmp/bow/pipeline/bear.png"
      assert PipelineUploader.url(file, :image_thumb1) == "tmp/bow/pipeline/thumb1_bear.png"
      assert PipelineUploader.url(file, :image_thumb2) == "tmp/bow/pipeline/thumb2_bear.png"
      assert PipelineUploader.url(file, :image_thumb3) == "tmp/bow/pipeline/thumb3_bear.png"
    end

    test "upload .txt and ignore it" do
      file = PipelineUploader.new(path: @file_memo)
      assert {:ok, []} = Bow.store(file)
    end
  end

  describe "Scoped uploader" do
    defmodule ScopedUploader do
      use Bow.Uploader

      def store_dir(file) do
        "scoped/#{file.scope.id}"
      end
    end

    test "store file in correct directory" do
      file = ScopedUploader.new(path: @file_cat, scope: %{id: 1})
      assert {:ok, _} = Bow.store(file)
      assert File.exists?("tmp/bow/scoped/1/cat.jpg")

      file = ScopedUploader.new(path: @file_bear, scope: %{id: 2})
      assert {:ok, _} = Bow.store(file)
      assert File.exists?("tmp/bow/scoped/2/bear.png")
    end

    test "load file from correct directory" do
      # store it first
      ScopedUploader.new(path: @file_cat, scope: %{id: 1}) |> Bow.store()

      # test loading
      file = ScopedUploader.new(name: "cat.jpg", scope: %{id: 1})
      assert {:ok, file} = Bow.load(file)
      assert file.path == "tmp/bow/scoped/1/cat.jpg"

      # test loading
      file = ScopedUploader.new(name: "cat.jpg", scope: %{id: 2})
      assert {:error, _} = Bow.load(file)
    end
  end

  describe "URL generation" do
    defmodule UrlUploader do
      use Bow.Uploader

      def filename(file, :original),  do: file.name
      def filename(file, :pdf),       do: "#{file.rootname}.pdf"
      def filename(file, :thumb),     do: "thumb_#{file.name}"
      def filename(file, :thumb_jpg), do: "thumb_#{file.rootname}.jpg"

      def store_dir(_) do
        "urls"
      end
    end

    test "uploader url" do
      file = UrlUploader.new(path: @file_bear)

      assert UrlUploader.url(file)              == "tmp/bow/urls/bear.png"
      assert UrlUploader.url(file, :pdf)        == "tmp/bow/urls/bear.pdf"
      assert UrlUploader.url(file, :thumb)      == "tmp/bow/urls/thumb_bear.png"
      assert UrlUploader.url(file, :thumb_jpg)  == "tmp/bow/urls/thumb_bear.jpg"
    end
  end

  describe "#combine_results" do
    test "empty" do
      assert Bow.combine_results([]) == {:ok, []}
    end

    test "all ok" do
      assert Bow.combine_results([
        {:avatar, {:ok, "data"}},
        {:photo,  {:ok, "cool"}}
      ]) == {:ok, [
        {:avatar, {:ok, "data"}},
        {:photo,  {:ok, "cool"}}
      ]}
    end

    test "with error" do
      assert Bow.combine_results([
        {:avatar, {:ok, "data"}},
        {:photo,  {:error, "wrong"}}
      ]) == {:error, [
        {:avatar, {:ok, "data"}},
        {:photo,  {:error, "wrong"}}
      ]}
    end
  end
end
