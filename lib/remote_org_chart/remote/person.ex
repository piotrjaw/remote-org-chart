defmodule RemoteOrgChart.Remote.Person do
  @moduledoc """
  A privacy-conscious projection of a Remote employment.
  """

  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :title,
    :department,
    :manager,
    :status,
    :employment_type,
    :employment_model
  ]

  @type summary :: %{id: String.t() | nil, name: String.t() | nil}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          title: String.t() | nil,
          department: summary() | nil,
          manager: summary() | nil,
          status: String.t() | nil,
          employment_type: String.t() | nil,
          employment_model: String.t() | nil
        }
end
