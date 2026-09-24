defmodule Bow.WithOutputTest do
  use ExUnit.Case

  @file_cat "test/files/cat.jpg"

  setup do
    File.write!("tmp/text.txt", "hello")
    source = Bow.new(path: "tmp/text.txt")
    target = Bow.set(source, :name, "upcase.md")

    {:ok, source: source, target: target}
  end

  test "sets written file path on target", %{source: source, target: target} do
    assert {:ok, %Bow{name: "upcase.md", path: path}} =
             Bow.with_output(target, fn output_path ->
               send(self(), {:output_path, output_path})
               File.write(output_path, source.path |> File.read!() |> String.upcase())
             end)

    assert File.read!(path) == "HELLO"
    assert_received {:output_path, output_path}
    assert Path.extname(output_path) == ".md"
    refute File.exists?(output_path)
  end

  test "returns error and removes partial output", %{target: target} do
    assert {:error, :boom} =
             Bow.with_output(target, fn output_path ->
               File.write!(output_path, "partial")
               send(self(), {:output_path, output_path})
               {:error, :boom}
             end)

    assert_received {:output_path, output_path}
    refute File.exists?(output_path)
  end

  test "output not written", %{target: target} do
    assert {:error, :output_not_found} = Bow.with_output(target, fn _output_path -> :ok end)
  end

  test "invalid return value", %{target: target} do
    assert_raise ArgumentError, ~r/expected :ok or {:error, reason}.*got: {"", 0}/, fn ->
      Bow.with_output(target, fn _output_path -> {"", 0} end)
    end
  end

  test "external command", %{source: source, target: target} do
    assert {:ok, %Bow{path: path}} =
             Bow.with_output(target, fn output_path ->
               case System.cmd("cp", [source.path, output_path]) do
                 {_, 0} -> :ok
                 {cmd_output, exit_code} -> {:error, exit_code: exit_code, output: cmd_output}
               end
             end)

    assert File.read!(path) == "hello"
  end

  test "works in uploader transform" do
    defmodule ThumbUploader do
      use Bow.Uploader

      def versions(_), do: [:original, :thumb]

      def transform(source, target, :thumb) do
        Bow.with_output(target, &File.cp(source.path, &1))
      end

      def transform(source, target, version), do: super(source, target, version)

      def store_dir(_), do: "with_output"
    end

    file = ThumbUploader.new(path: @file_cat)
    assert {:ok, _} = Bow.store(file)
    assert File.read!("tmp/bow/with_output/thumb_cat.jpg") == File.read!(@file_cat)
  end
end
