defmodule Bow.Storage do
  @typep path :: Path.t
  @typep dir  :: Path.t
  @typep name :: Path.t
  @typep opts :: keyword


  @doc """
  Store file in storage
  """
  @callback store(path, dir, name, opts) ::
    :ok | {:error, any}

  @doc """
  Load file from storage
  """
  @callback load(dir, name, opts) ::
    {:ok, path} | {:error, any}

  @doc """
  Delete file in storage
  """
  @callback delete(dir, name, opts) ::
    :ok | {:error, any}

  @doc """
  Generate file URL
  """
  @callback delete(dir, name, opts) ::
    :ok | {:error, any}

end
