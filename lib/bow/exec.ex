defmodule Bow.Exec do
  @moduledoc """
  Transform files with shell commands

  This module allows executing any external command taking care of temporary path generation and error handling.
  It is as reliable as [erlexec](https://github.com/saleyn/erlexec) module (very!).

  It is also possible to provide custom command timeout. See `exec/4` to see all available options.
  """

  defp default_timeout, do: Application.get_env(:bow, :exec_timeout, 15_000)

  @doc """
  Execute command

  Arguments:
  - `source` - source file to be transformed
  - `target_name` - target file
  - `command` - the command to be executed. Placeholders `${input}` and `${output}` will be replaced with source and target paths

  Options:
  - `:timeout` - time in which the command must return. If it's exceeded the command process will be killed.

  Examples

      # generate image thumbnail from first page of pdf
      def transform(file, :pdf_thumbnail) do
        Bow.Exec.exec file, filename(file, :pdf_thumbnail),
          "convert '${input}[0]' -strip -gravity North -background '#ffffff'" <>
                            " -resize 250x175^ -extent 250x175 -format png png:${output}"
      end

  """
  @spec exec(Bow.t, Bow.t, String.t, keyword) :: {:ok, Bow.t} | {:error, any}
  def exec(source, target, command, opts \\ []) do
    timeout = opts[:timeout] || default_timeout()

    source_path = source.path
    target_path = Plug.Upload.random_file!("bow-exec")

    cmd = command
      |> String.replace("${input}", source_path)
      |> String.replace("${output}", target_path)
      |> to_charlist

    trapping fn ->
      case :exec.run_link(cmd, [stdout: self(), stderr: self()]) do
        {:ok, pid, ospid} ->
          case wait_for_exit(pid, ospid, timeout) do
            {:ok, output} ->
              if File.exists?(target_path) do
                {:ok, Bow.set(target, :path, target_path)}
              else
                {:error, reason: :file_not_found, output: output, exit_code: 0, cmd: cmd}
              end

            {:error, exit_code, output} ->
              {:error, output: output, exit_code: exit_code, cmd: cmd}
          end
        error ->
          error
      end
    end
  end

  defp trapping(fun) do
    trap = Process.flag(:trap_exit, true)
    result = fun.()
    Process.flag(:trap_exit, trap)
    result
  end

  defp wait_for_exit(pid, ospid, timout) do
    receive do
      {:EXIT, ^pid, :normal}              -> {:ok, receive_output(ospid)}
      {:EXIT, ^pid, {:exit_status, code}} -> {:error, code, receive_output(ospid)}
    after
      timout ->
        :exec.stop_and_wait(pid, 2000)
        {:error, :timeout, receive_output(ospid)}
    end
  end

  defp receive_output(ospid, output \\ []) do
    receive do
      {:stdout, ^ospid, data} -> receive_output(ospid, [output, data])
      {:stderr, ^ospid, data} -> receive_output(ospid, [output, data])
    after
      0 -> output |> to_string
    end
  end
end
