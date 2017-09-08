defmodule Bow.Storage.Local do
  @behaviour Bow.Storage

  defp prefix, do: Application.get_env(:bow, :storage_prefix, "tmp/bow")

  def store(file_path, dir, name, _opts) do
    dir   = Path.join([prefix(), dir])
    path  = Path.join([dir, name])

    File.mkdir_p!(dir)
    File.cp!(file_path, path)

    :ok
  end

  def load(dir, name, _opts) do
    # no need to download this file - just point to directly
    path = Path.join([prefix(), dir, name])
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :file_not_found}
    end
  end

  def delete(dir, name, _opts) do
    path = Path.join([prefix(), dir, name])
    if File.exists?(path) do
      File.rm(path)
      :ok
    else
      {:error, :file_not_found}
    end
  end

  def url(dir, name, _opts) do
    Path.join([prefix(), dir, name])
  end

  def reset! do
    File.rm_rf!(prefix())
  end
end
