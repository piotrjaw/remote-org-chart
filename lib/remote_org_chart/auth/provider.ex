defmodule RemoteOrgChart.Auth.Provider do
  @moduledoc """
  Supplies the single application-level reviewer credential pair.
  """

  @callback credentials() ::
              {:ok, %{username: String.t(), password: String.t()}}
              | {:error, term()}
end
