defmodule FooTest do
  use ExUnit.Case

  test "success" do
    assert "success" == "success"
  end

  test "failure" do
    assert "success" != "failure"
  end
end
