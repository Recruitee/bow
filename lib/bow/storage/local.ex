defmodule Bow.Storage.Local do
  @behaviour Bow.Storage

  defp prefix, do: Application.get_env(:bow, :storage_prefix, "tmp/bow")

  @impl true
  def store(file_path, dir, name, _opts) do
    dir = Path.join([prefix(), dir])
    path = Path.join([dir, name])

    File.mkdir_p!(dir)
    File.cp!(file_path, path)

    :ok
  end

  @impl true
  def load(dir, name, _opts) do
    # no need to download this file - just point to directly
    path = Path.join([prefix(), dir, name])

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :file_not_found}
    end
  end

  @impl true
  def delete(dir, name, _opts) do
    path = Path.join([prefix(), dir, name])
    File.rm(path)
  end

  @impl true
  def copy(src_dir, src_name, dst_dir, dst_name, _opts) do
    dst_dir = Path.join([prefix(), dst_dir])
    dst_path = Path.join([dst_dir, dst_name])
    src_path = Path.join([prefix(), src_dir, src_name])

    File.mkdir_p!(dst_dir)
    File.cp(src_path, dst_path)
  end

  @impl true
  def url(dir, name, _opts) do
    Path.join([prefix(), dir, name])
  end

  def reset! do
    File.rm_rf!(prefix())
  end
end
