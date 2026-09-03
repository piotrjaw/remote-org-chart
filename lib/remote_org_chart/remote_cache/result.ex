defmodule RemoteOrgChart.RemoteCache.Result do
  @moduledoc """
  A normalized chart plus cache metadata safe for API serialization.
  """

  alias RemoteOrgChart.Hierarchy.Chart

  @enforce_keys [:chart, :fetched_at, :stale]
  defstruct [:chart, :fetched_at, :stale]

  @type t :: %__MODULE__{
          chart: Chart.t(),
          fetched_at: DateTime.t(),
          stale: boolean()
        }
end
