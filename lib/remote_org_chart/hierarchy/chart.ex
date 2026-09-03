defmodule RemoteOrgChart.Hierarchy.Chart do
  @moduledoc """
  A deterministic organization forest ready for caching and serialization.
  """

  alias RemoteOrgChart.Hierarchy.Node
  alias RemoteOrgChart.Remote.Company

  @enforce_keys [:company, :roots, :warnings, :employee_count, :root_count]
  defstruct [:company, :roots, :warnings, :employee_count, :root_count]

  @type t :: %__MODULE__{
          company: Company.t(),
          roots: [Node.t()],
          warnings: [map()],
          employee_count: non_neg_integer(),
          root_count: non_neg_integer()
        }
end
