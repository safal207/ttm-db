defmodule TTM.ProjectionsTest do
  use ExUnit.Case, async: true

  test "rebuild consumes stream (placeholder)" do
    assert {:error, :not_implemented} = TTM.Projections.rebuild(:dummy)
  end

  test "list returns projections" do
    assert TTM.Projections.list() == []
  end
end
