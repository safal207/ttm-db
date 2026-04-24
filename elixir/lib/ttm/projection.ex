defmodule TTM.Projection do
  @moduledoc """
  Behaviour for rebuildable projections.
  """

  @callback name() :: String.t()
  @callback init() :: term()
  @callback apply(map(), term()) :: term()
  @callback finalize(term()) :: term()

  @optional_callbacks finalize: 1
end
