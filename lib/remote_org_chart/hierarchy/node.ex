defmodule RemoteOrgChart.Hierarchy.Node do
  @moduledoc """
  A person plus their recursively nested direct reports.
  """

  @enforce_keys [:id, :name, :reports]
  defstruct [
    :id,
    :name,
    :title,
    :department,
    :manager,
    :status,
    :employment_type,
    :employment_model,
    :reports,
    manager_archived: false
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          title: String.t() | nil,
          department: map() | nil,
          manager: map() | nil,
          manager_archived: boolean(),
          status: String.t() | nil,
          employment_type: String.t() | nil,
          employment_model: String.t() | nil,
          reports: [t()]
        }
end
