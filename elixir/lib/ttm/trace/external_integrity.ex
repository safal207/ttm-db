defmodule TTM.Trace.ExternalIntegrity do
  @moduledoc """
  Integrity adapter bridge for wiring an external T-Trace verifier.

  Configure verifier as `:trace_verify_mfa` in the form:
  - `{Module, :function}`
  - `{Module, :function, extra_args}`

  The verifier will be called as `function(seal, record, ...extra_args)`.
  """

  @behaviour TTM.Trace.Integrity

  @impl true
  def verify(seal, record) do
    case Application.get_env(:ttm, :trace_verify_mfa) do
      {mod, fun} when is_atom(mod) and is_atom(fun) ->
        apply(mod, fun, [seal, record])

      {mod, fun, extra_args} when is_atom(mod) and is_atom(fun) and is_list(extra_args) ->
        apply(mod, fun, [seal, record | extra_args])

      _ ->
        {:error, :verify_not_configured}
    end
  rescue
    UndefinedFunctionError -> {:error, :verify_unavailable}
  end
end
