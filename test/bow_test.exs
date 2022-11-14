defmodule BowTest do
  use ExUnit.Case

  setup do
    Bow.Storage.Local.reset!()
    :ok
  end

  defmodule Convert do
    def copy(source, target) do
      with {:ok, path} <- Plug.Upload.random_file("bow"),
           :ok <- File.cp(source.path, path) do
        {:ok, %{target | path: path}}
      end
    end
  end

  @file_cat "test/files/cat.jpg"
  @file_bear "test/files/bear.png"
  @file_roomba "test/files/roomba.gif"
  @file_report "test/files/report.pdf"
  @file_cv "test/files/cv.docx"
  @file_memo "test/files/memo.txt"

  describe "#new" do
    test "raise when no name nor path" do
      assert_raise Bow.Error, fn ->
        # typos are intentional
        Bow.new(nmae: "cat.jpg", phat: "path/to/cat.jpg")
      end
    end

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

  describe "#set" do
    test "set :name" do
      file =
        Bow.new(name: "file.png")
        |> Bow.set(:name, "new.jpg")

      assert file.name == "new.jpg"
      assert file.ext == ".jpg"
      assert file.rootname == "new"
    end

    test "set :rootname" do
      file =
        Bow.new(name: "file.png")
        |> Bow.set(:ext, ".jpg")

      assert file.name == "file.jpg"
      assert file.ext == ".jpg"
      assert file.rootname == "file"
    end

    test "set :ext" do
      file =
        Bow.new(name: "file.png")
        |> Bow.set(:rootname, "new")

      assert file.name == "new.png"
      assert file.ext == ".png"
      assert file.rootname == "new"
    end

    test "set :other" do
      file =
        Bow.new(name: "file.png")
        |> Bow.set(:path, "some/path")

      assert file.name == "file.png"
      assert file.ext == ".png"
      assert file.rootname == "file"
      assert file.path == "some/path"
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

    test "#delete" do
      # store it first
      MinimalUploader.new(path: @file_cat) |> Bow.store()

      # then test delete
      file = MinimalUploader.new(name: "cat.jpg")
      assert :ok = Bow.delete(file)
      refute File.exists?("tmp/bow/minimal/cat.jpg")
    end
  end

  describe "Generate thumbs" do
    defmodule ThumbnailUploader do
      use Bow.Uploader

      def versions(file) do
        case file.ext do
          ".jpg" -> [:original, :thumb]
          ".gif" -> [:thumb]
          _ -> []
        end
      end

      def transform(source, target, :original), do: transform_original(source, target)

      def transform(source, target, :thumb) do
        Convert.copy(source, target)
      end

      def filename(file, :original), do: file.name
      def filename(file, version), do: "#{version}_#{file.name}"

      def store_dir(_file) do
        "thumbnail"
      end
    end

    test "upload .jpg and thumb file in correct directory" do
      file = ThumbnailUploader.new(path: @file_cat)
      assert {:ok, results} = Bow.store(file)
      assert results.original == :ok
      assert results.thumb == :ok

      assert File.exists?("tmp/bow/thumbnail/cat.jpg")
      assert File.exists?("tmp/bow/thumbnail/thumb_cat.jpg")

      assert File.read!(@file_cat) == File.read!("tmp/bow/thumbnail/cat.jpg")
    end

    test "upload .gif but store only thumb" do
      file = ThumbnailUploader.new(path: @file_roomba)
      assert {:ok, results} = Bow.store(file)
      assert results.thumb == :ok
      refute results[:original]

      refute File.exists?("tmp/bow/thumbnail/roomba.gif")
      assert File.exists?("tmp/bow/thumbnail/thumb_roomba.gif")
    end
  end

  describe "Transform pipeline" do
    defmodule PipelineUploader do
      use Bow.Uploader

      def versions(file) do
        case file.ext do
          # for pdf, store original and make thumb
          ".pdf" -> [:original, :thumb]
          # for doc, store original and generate pdf
          ".docx" -> [:original, :pdf]
          ".png" -> [:original, :image_thumb1]
          # ignore the rest
          _ -> []
        end
      end

      # do nothing with original file
      def transform(source, target, :original), do: transform_original(source, target)

      # convert to pdf
      def transform(source, target, :pdf) do
        with {:ok, pdf} <- Convert.copy(source, target) do
          # and then convert to thumb
          {:ok, pdf, [:thumb]}
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
      def filename(file, :original), do: file.name
      def filename(file, :pdf), do: "#{file.rootname}.pdf"
      def filename(file, :thumb), do: "thumb_#{file.rootname}.png"
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

      assert results == %{
               original: :ok,
               thumb: :ok
             }

      assert File.exists?("tmp/bow/pipeline/report.pdf")
      assert File.exists?("tmp/bow/pipeline/thumb_report.png")
    end

    test "upload .doc, generate pdf and pdf thumb image" do
      file = PipelineUploader.new(path: @file_cv)
      assert {:ok, results} = Bow.store(file)

      assert results == %{
               original: :ok,
               pdf: :ok,
               thumb: :ok
             }

      assert File.exists?("tmp/bow/pipeline/cv.docx")
      assert File.exists?("tmp/bow/pipeline/cv.pdf")
      assert File.exists?("tmp/bow/pipeline/thumb_cv.png")
    end

    test "upload .png and generate three nested thumbnails" do
      file = PipelineUploader.new(path: @file_bear)
      assert {:ok, results} = Bow.store(file)

      assert results == %{
               original: :ok,
               image_thumb1: :ok,
               image_thumb2: :ok,
               image_thumb3: :ok
             }

      assert File.exists?("tmp/bow/pipeline/bear.png")
      assert File.exists?("tmp/bow/pipeline/thumb1_bear.png")
      assert File.exists?("tmp/bow/pipeline/thumb2_bear.png")
      assert File.exists?("tmp/bow/pipeline/thumb3_bear.png")

      assert Bow.url(file) == "tmp/bow/pipeline/bear.png"
      assert Bow.url(file, :image_thumb1) == "tmp/bow/pipeline/thumb1_bear.png"
      assert Bow.url(file, :image_thumb2) == "tmp/bow/pipeline/thumb2_bear.png"
      assert Bow.url(file, :image_thumb3) == "tmp/bow/pipeline/thumb3_bear.png"
    end

    test "upload .txt and ignore it" do
      file = PipelineUploader.new(path: @file_memo)
      assert {:ok, %{}} = Bow.store(file)
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

      def filename(file, :original), do: file.name
      def filename(file, :pdf), do: "#{file.rootname}.pdf"
      def filename(file, :thumb), do: "thumb_#{file.name}"
      def filename(file, :thumb_jpg), do: "thumb_#{file.rootname}.jpg"

      def store_dir(_) do
        "urls"
      end
    end

    test "uploader url" do
      file = UrlUploader.new(path: @file_bear)

      assert Bow.url(file) == "tmp/bow/urls/bear.png"
      assert Bow.url(file, :pdf) == "tmp/bow/urls/bear.pdf"
      assert Bow.url(file, :thumb) == "tmp/bow/urls/thumb_bear.png"
      assert Bow.url(file, :thumb_jpg) == "tmp/bow/urls/thumb_bear.jpg"
    end

    test "handle nil gracefully" do
      assert Bow.url(nil) == nil
    end
  end

  describe "#combine_results" do
    test "empty" do
      assert Bow.combine_results([]) == {:ok, %{}}
    end

    test "all ok" do
      assert Bow.combine_results([
               {:avatar, {:ok, "data"}},
               {:photo, :ok}
             ]) ==
               {:ok,
                %{
                  avatar: {:ok, "data"},
                  photo: :ok
                }}
    end

    test "with error" do
      assert Bow.combine_results([
               {:avatar, {:ok, "data"}},
               {:photo, {:error, "wrong"}}
             ]) ==
               {:error,
                %{
                  avatar: {:ok, "data"},
                  photo: {:error, "wrong"}
                }}
    end
  end

  describe "Failing conversion" do
    defmodule ErrorUploader do
      use Bow.Uploader

      def versions(_), do: [:original, :pdf]

      def transform(source, target, :original), do: transform_original(source, target)
      def transform(_source, _target, :pdf), do: {:error, "oups"}

      def store_dir(_), do: "error"
    end

    defmodule RaiseUploader do
      use Bow.Uploader

      def versions(_), do: [:original, :pdf]

      def transform(source, target, :original), do: transform_original(source, target)
      def transform(_source, _target, :pdf), do: %{}.foo + 1

      def store_dir(_), do: "raise"
    end

    test "error when generating version" do
      file = ErrorUploader.new(path: @file_cv)
      assert {:error, results} = Bow.store(file)

      assert :ok = results[:original]
      assert {:error, "oups"} = results[:pdf]

      assert File.exists?("tmp/bow/error/cv.docx")
      refute File.exists?("tmp/bow/error/pdf_cv.docx")
    end

    test "raise when generating version" do
      file = RaiseUploader.new(path: @file_cv)
      assert {:error, results} = Bow.store(file)

      assert :ok = results[:original]
      assert {:error, %KeyError{}} = results[:pdf]

      assert File.exists?("tmp/bow/raise/cv.docx")
      refute File.exists?("tmp/bow/raise/pdf_cv.docx")
    end
  end

  describe "Regenerate versions" do
    defmodule V1 do
      use Bow.Uploader

      def store_dir(_) do
        "regenerate"
      end
    end

    defmodule V2 do
      use Bow.Uploader

      def versions(_), do: [:original, :thumb]

      def store_dir(_) do
        "regenerate"
      end
    end

    test "regenerate versions when updating uploader" do
      file = V1.new(path: @file_cat)
      {:ok, _} = Bow.store(file)

      assert File.exists?("tmp/bow/regenerate/cat.jpg")
      refute File.exists?("tmp/bow/regenerate/thumb_cat.jpg")

      file = V2.new(path: @file_cat)
      {:ok, _} = Bow.regenerate(file)

      assert File.exists?("tmp/bow/regenerate/cat.jpg")
      assert File.exists?("tmp/bow/regenerate/thumb_cat.jpg")
    end
  end

  describe "Copy" do
    defmodule CopyUploader do
      use Bow.Uploader

      def versions(_), do: [:original, :thumb]

      def transform(source, target, :original), do: transform_original(source, target)
      def transform(source, target, :thumb), do: Convert.copy(source, target)

      def filename(file, :original), do: file.name
      def filename(file, version), do: "#{version}_#{file.name}"

      def store_dir(_) do
        "copy"
      end
    end

    defmodule CopyWrongUploader do
      use Bow.Uploader

      def store_dir(_) do
        "copywrong"
      end
    end

    test "#copy" do
      file = CopyUploader.new(path: @file_cat)
      assert {:ok, _results} = Bow.store(file)

      copy = Bow.set(file, :rootname, "kitten")
      assert {:ok, results} = Bow.copy(file, copy)

      assert results == %{
               original: :ok,
               thumb: :ok
             }

      assert File.exists?("tmp/bow/copy/cat.jpg")
      assert File.exists?("tmp/bow/copy/kitten.jpg")
      assert File.exists?("tmp/bow/copy/thumb_cat.jpg")
      assert File.exists?("tmp/bow/copy/thumb_kitten.jpg")

      assert File.read!(@file_cat) == File.read!("tmp/bow/copy/cat.jpg")
      assert File.read!(@file_cat) == File.read!("tmp/bow/copy/kitten.jpg")

      assert File.read!("tmp/bow/copy/thumb_cat.jpg") ==
               File.read!("tmp/bow/copy/thumb_kitten.jpg")
    end

    test "error on uploader mismatch" do
      file = CopyUploader.new(path: @file_cat)
      copy = CopyWrongUploader.new(path: @file_cat, rootname: "kitten")

      assert {:error, :uploader_mismatch} = Bow.copy(file, copy)
    end
  end

  describe "Custom assets host uploader" do
    defmodule AssetsHostUploader do
      use Bow.Uploader

      def store_dir(_) do
        "minimal"
      end

      def assets_host do
        "https://bow.dev/"
      end
    end

    test "#store" do
      file = AssetsHostUploader.new(path: @file_cat)
      assert {:ok, _results} = Bow.store(file)
      assert "https://bow.dev/" <> _ = Bow.url(file)
    end
  end
end
