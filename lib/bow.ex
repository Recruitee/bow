defmodule Bow do
  @moduledoc """
  Bow - the file uploader


  ## Global Configuration

      config :bow,
        storage: Bow.Storage.Local,             # storage adapter; Bow.Storage.Local or Bow.Storage.S3
        storage_prefix: "priv/static/uploads",  # storage directory prefix

        store_timeout:  30_000,                 # single version upload timeout
        exec_timeout:   15_000,                 # single command execution timeout
  """

  def storage,          do: Application.get_env(:bow, :storage, Bow.Storage.Local)
  def store_timeout,    do: Application.get_env(:bow, :store_timeout, 30_000)
  def version_timeout,  do: Application.get_env(:bow, :version_timeout, 60_000)

  @type t :: %__MODULE__{
            name:     String.t, # "cat.jpg",  "README"
            rootname: String.t, # "cat",      "README"
            ext:      String.t, # ".jpg",     ""
            path:     String.t | nil,
            scope:    any,
            uploader: atom
  }

  @typep opts :: keyword

  @enforce_keys [:name, :rootname, :ext]
  defstruct name:     "",
            rootname: "",
            ext:      nil,
            path:     nil,
            scope:    nil,
            uploader: nil


  defmodule Error do
    defexception message: ""
  end

  @doc """
  Process & store given file with its uploader
  """
  @spec store(t, opts) :: {:ok, t} | {:error, any}
  def store(file, opts \\ []) do
    uploader = file.uploader
    versions = uploader.versions(file)

    make(uploader, file, file, versions, opts) |> combine_results
  end


  @doc """
  Load given file
  """
  @spec load(t, opts) :: {:ok, t} | {:error, any}
  def load(file, opts \\ []) do
    with {:ok, path} <- load_file(file.uploader, file, opts) do
      {:ok, %{file | path: path}}
    end
  end

  @doc """
  Delete all versions of given file
  """
  @spec delete(t, opts) :: :ok
  def delete(file, opts \\ []) do
    uploader = file.uploader
    for version <- uploader.versions(file) do
      name = uploader.filename(file, version)
      delete_file(uploader, set(file, :name, name), opts)
    end

    :ok
  end

  def regenerate(file) do
    file |> load |> store
  end

  defp make(up, f0, fx, versions, opts) when is_list(versions) do
    versions
    |> Enum.map(&Task.async(fn -> make(up, f0, fx, &1, opts) end))
    |> Enum.map(&Task.await(&1, version_timeout()))
    |> List.flatten
  end

  defp make(up, f0, fx, version, opts) do
    fy = fx
      |> set(:name, up.filename(f0, version))
      |> set(:path, nil)

    case transform(up, fx, fy, version) do
      {:ok, fy, next_versions} ->
        res0 = Task.async(fn -> store_file(up, fy, opts) end)
        res1 = make(up, f0, fy, next_versions, opts)
        [{version, Task.await(res0, store_timeout())} | res1]

      {:ok, fy} ->
        [{version, store_file(up, fy, opts)}]

      :ok ->
        [{version, {:ok, :no_store}}]

      {:error, reason} ->
        [{version, {:error, reason}}]
    end
  end

  defp transform(up, fx, fy, version) do
    up.transform(fx, fy, version)
  rescue
    ex -> {:error, ex}
  end

  defp store_file(uploader, file, opts) do
    storage().store(
      file.path,
      uploader.store_dir(file),
      file.name,
      opts ++ uploader.store_options(file)
    )
  end

  defp load_file(uploader, file, opts) do
    storage().load(
      uploader.store_dir(file),
      file.name,
      opts
    )
  end

  defp delete_file(uploader, file, opts) do
    storage().delete(
      uploader.store_dir(file),
      file.name,
      opts
    )
  end

  def url(file), do: url(file, [])
  def url(file, opts) when is_list(opts), do: url(file, :original, opts)
  def url(file, version), do: url(file, version, [])
  def url(nil, _version, _opts), do: nil
  def url(file, version, opts) do
    file = resolve_scope(file)

    storage().url(
      file.uploader.store_dir(file),
      file.uploader.filename(file, version),
      opts
    )
  end

  defp resolve_scope({file, scope}), do: set(file, :scope, scope)
  defp resolve_scope(file), do: file

  def new(args) do
    {name, path} = case {args[:name], args[:path]} do
      {nil, nil}    -> raise Error, message: "Missing :name or :path attributes when creating new Bow file"
      {nil, path}   -> {basename(path), path}
      {name, path}  -> {name, path}
    end

    args = Keyword.merge(args, [
      path:     path,
      name:     name,
      rootname: rootname(name),
      ext:      extname(name)
    ])

    struct!(__MODULE__, args)
  end

  defp basename(name), do: name |> Path.basename()
  defp rootname(name), do: name |> Path.rootname()
  defp extname(name), do: name |> Path.extname() |> String.downcase()

  def set(file, :name, name), do:
    %{file | name: name, rootname: rootname(name), ext: extname(name)}
  def set(file, :rootname, rootname), do:
    %{file | name: rootname <> file.ext, rootname: rootname}
  def set(file, :ext, ext), do:
    %{file | name: file.rootname <> ext, ext: ext}
  def set(file, key, value), do:
    struct(file, [{key, value}])

  def combine_results(results) do
    if Enum.any?(results, &match?({_, {:error, _}}, &1)) do
      {:error, results}
    else
      {:ok, results}
    end
  end
end
