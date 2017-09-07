defmodule BowTest do
  use ExUnit.Case
  doctest Bow

  test "greets the world" do
    assert Bow.hello() == :world
  end
end
