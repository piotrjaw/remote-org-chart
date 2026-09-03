defmodule RemoteOrgChart.Remote.Snapshot do
  @moduledoc """
  A normalized company and its employments, ready for hierarchy construction.
  """

  alias RemoteOrgChart.Remote.{Company, Person}

  @enforce_keys [:company, :people, :warnings]
  defstruct [:company, :people, :warnings]

  @type t :: %__MODULE__{
          company: Company.t(),
          people: [Person.t()],
          warnings: [map()]
        }
end
