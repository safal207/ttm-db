defmodule TTM.Trace.Store do
  @moduledoc """
  Storage contract for append-only trace records.
  """

  @type record :: map()

  @callback append(record()) :: :ok | {:error, term()}
  @callback stream(keyword()) :: Enumerable.t()
end
