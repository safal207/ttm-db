defmodule TTM.Trace.Integrity do
  @moduledoc """
  Integrity verification boundary for T-Trace integration.

  TTM DB does not define integrity rules; it delegates verification here.
  """

  @callback verify(seal :: term(), record :: map()) :: :ok | {:error, term()}
end
