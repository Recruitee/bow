defmodule Bow.ExecTest do
  use ExUnit.Case

  @file_cat "test/files/cat.jpg"

  import Bow.Exec, only: [exec: 3, exec: 4]

  setup do
    source = Bow.new(path: @file_cat)
    target = Bow.set(source, :name, "thumb_#{source.name}")

    {:ok, source: source, target: target}
  end

  test "successful command", %{source: source, target: target} do
    assert {:ok, %Bow{path: path}} = exec(source, target, "test/scripts/copy.sh ${input} ${output}")
    assert path != nil
    assert File.exists?(path)
  end

  test "command not found", %{source: source, target: target} do
    assert {:error, reason} = exec(source, target, "test/scripts/notfound ${input} ${output}")
    assert reason[:output] =~ ~r/no such file/u
  end

  test "failing command", %{source: source, target: target} do
    assert {:error, reason} = exec(source, target, "test/scripts/fail.sh ${input} ${output}")
    assert reason[:exit_code] != 0
  end

  test "timout", %{source: source, target: target} do
    assert {:error, reason} = exec(source, target, "test/scripts/sleep.sh ${input} ${output}", timeout: 500)
    assert reason[:exit_code] == :timeout
  end
end
