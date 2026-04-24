defmodule TTM.Trace.NoopIntegrity do
  @moduledoc """
  Default integrity adapter used until a concrete T-Trace verifier is wired.
  """

  @behaviour TTM.Trace.Integrity

  @impl true
  def verify(_seal, _record), do: {:error, :not_implemented}
end
