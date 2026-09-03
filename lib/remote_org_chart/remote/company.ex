defmodule RemoteOrgChart.Remote.Company do
  @moduledoc """
  The small company projection used by the organization chart.
  """

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{id: String.t(), name: String.t()}
end
