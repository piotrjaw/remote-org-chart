defmodule RemoteOrgChart.Remote.Error do
  @moduledoc """
  A safe, typed failure returned by the Remote integration boundary.
  """

  @enforce_keys [:kind]
  defstruct [:kind, :operation, :retry_after]

  @type kind :: :authentication | :temporary | :invalid_response | :internal

  @type t :: %__MODULE__{
          kind: kind(),
          operation: atom() | nil,
          retry_after: non_neg_integer() | nil
        }

  @spec invalid_response(atom()) :: t()
  def invalid_response(operation), do: %__MODULE__{kind: :invalid_response, operation: operation}
end
