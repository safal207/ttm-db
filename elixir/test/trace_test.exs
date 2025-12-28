defmodule TTM.TraceTest do
  use ExUnit.Case, async: true

  test "append adds records (placeholder)" do
    assert {:error, :not_implemented} = TTM.Trace.append(%{})
  end

  test "stream yields an enumerable" do
    assert Enum.to_list(TTM.Trace.stream()) == []
  end
end
