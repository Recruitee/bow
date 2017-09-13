defmodule Bow.Uploader do
  @moduledoc """
  Base module for definig uploaders

  ## Definition

  Minimal usage example:

      defmodule MyUploader do
        use Bow.Uploader

        # specify storage directory
        def store_dir(_file) do
          "uploads"
        end
      end


  Full example


      defmodule AttachmentUploader do
        use Bow.Uploader

        # define what versions to generate for given file
        def versions(_file) do
          [:original, :thumb]
        end


        # keep the origianal file name
        def filename(file, :original), do: file.name

        # prepend "thumb_" for thumbnail
        def filename(file, :thumb),    do: "thumb_\#{file.name}"


        # do nothing with original file
        def transform(file, :original), do: transform_original(file)

        # generate image thumbnail
        def transform(source, target, :thumb) do
          Bow.Exec.exec source, target,
            "convert ${input} -strip -gravity Center -resize 250x175^ -extent 250x175 ${output}"
        end


        # specify storage directory
        def store_dir(file) do
          "attachments/\#{file.scope.id}"
        end

        # specify storage options
        def store_options(_file) do
          %{acl: :private}
        end
      end


  ## Direct usage

      file = MyUploader.new("path/to/file")
      Bow.store(file)

      # you can optionally specify custom name and/or scope
      file = MyUploader.new("path/to/file", name: "avatar.png", scope: %{id: 1})

  ## Integration with Ecto

  See `Bow.Ecto` for usage with `Ecto.Schema`
  """


  @doc """
  Defines storage dir for given file.

  There is no default implementation - it must be provided by uploader

  Simple usage

      defmodule MyUploader do
        # ...
        def store_dir(_file) do
          "uploads"
        end
      end

  Usage with `scope` (usually when using Bow.Ecto)

      defmodule MyUploader do
        # ...
        def store_dir(file) do
          "attachments/\#{file.scope.id}"
        end
      end

  """
  @callback store_dir(file :: Bow.t) :: String.t

  @doc """
  Defines store custom options.

  Default implementation returns empty map (`%{}`)

  Example usage with `Bow.Storage.S3`

      defmodule MyUploader do
        # ...
        def store_options(_file) do
          %{acl: :private}
        end
      end

  """
  @callback store_options(file :: Bow.t) :: map()

  @doc """
  Return list of versions to be generated for given file.

  The default returns a list with single element - `[:original]`

  Simple definition:

      defmodule MyImageUploader do
        # ...
        def versions(_file) do
          [:original, :thumb]
        end
      end


  Custom logic based on input file:

      defmodule MyDocumentUploader do
        # ...
        def versions(file) do
          case file.ext do
            ".pdf" -> [:original]
            ".doc" -> [:original, :pdf] # generate :pdf version for .doc files
          end
        end
      end

  """
  @callback versions(file :: Bow.t) :: [atom]


  @doc """
  Customize filenames for given version.

  The default implementation uses original filename for `:original` version and others are prefixed with `"\#{version}_"`

  **IMPORTANT: This function is used both when uploading files and when generating URLs so it must be stable.**

  Example

      defmodule MyImageUploader do
        # keep the origianal file name
        def filename(file, :original),  do: file.name

        # for :pdf version prefix with _pdf and add .pdf extension
        def filename(file, :pdf),       do: "pdf_\#{file.rootname}.pdf"

        # for any other version prefix with version name
        def filename(file, version),     do: "\#{version}_\#{file.name}"
      end
  """
  @callback filename(file :: Bow.t, version :: atom) :: String.t


  @doc """
  Define transformation to given version.

  The return value can be either:
  - `{:ok, transformed_file}` - when transformation is successful
  - `{:ok, transformed_file. next_versions}` - when transformation is successful and other versions should be generated based on this one (instead of the original file)
  - `{:error, reason}` - in case transformation failure

  Example

      defmodule MyImageUploader do
        # generate image thumbnail
        def transform(source, target, :thumb) do
          # Bow.Exec allows executing any system command replacing ${input} and ${output}
          # with correct paths. It can also take :timeout option to prevent resource consumtion.
          # Refer to Bow.Exec documentation for more details
          Bow.Exec.exec source, target,
            "convert ${input} -strip -gravity Center -resize 250x175^ -extent 250x175 ${output}"
        end
      end

  Derived versions generation

      defmodule MyImageUploader do
        # generate image thumbnail and then micro_thumb version based on that
        def transform(source, target, :thumb) do
          with {:ok, thumb_file} <- Bow.Exec.exec source, target
            "convert ${input} -strip -gravity Center -resize 250x175^ -extent 250x175 ${output}" do
            {:ok, thumb_file, [:micro_thumb]}
          end
        end
      end
  """
  @callback transform(source :: Bow.t, target :: Bow.t, version :: atom) ::
    {:ok, target :: Bow.t} |
    {:ok, target :: Bow.t, next_versions :: [atom]} |
    {:error, reason :: any}

  @doc """
  Validate incoming file before processing.

  Mostly useful in conjunction with `validate_changeset/2` from Bow.Ecto module.
  The default implementation simply returns `:ok`

  Example

      defmodule MyImageUploader do
        def validate(%{ext: ext}) when ext in ~w(.jpg .png), do: :ok
        def validate(_), do: {:error, :extension_not_allowed}
      end
  """
  @callback validate(file :: Bow.t) :: :ok | {:error, reason :: any}


  defmacro __using__(_) do
    quote do
      @behaviour Bow.Uploader
      import Bow.Uploader

      def new(args) do
        args
        |> Bow.new()
        |> Bow.set(:uploader, __MODULE__)
      end

      # default store options
      def store_options(_file), do: []
      defoverridable [store_options: 1]

      # by default always store just the original
      def versions(_), do: [:original]
      defoverridable [versions: 1]

      # by default use original file name
      def filename(file, :original),  do: file.name
      def filename(file, version),    do: "#{version}_#{file.name}"
      defoverridable [filename: 2]

      # by default do nothing with original (use the same path)
      def transform(source, target, _version), do: transform_original(source, target)
      defoverridable [transform: 3]

      # by default every file is valid
      def validate(file), do: :ok
      defoverridable [validate: 1]
    end
  end

  def transform_original(source, target), do: {:ok, %{target | path: source.path}}
end
