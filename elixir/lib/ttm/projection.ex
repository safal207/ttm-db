defmodule TTM.Projection do
  @moduledoc """
  Behaviour for rebuildable projections.
  """

  @callback name() :: String.t()
  @callback init() :: term()
  @callback apply(map(), term()) :: term()
  @callback finalize(term()) :: term()
end
