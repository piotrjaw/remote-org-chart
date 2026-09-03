defmodule RemoteOrgChart.Remote.Source do
  @moduledoc """
  Contract shared by live and fixture-backed Remote data providers.
  """

  alias RemoteOrgChart.Remote.Error

  @type result :: %{
          identity: map(),
          employments: [map()],
          page_count: pos_integer()
        }

  @callback fetch(keyword()) :: {:ok, result()} | {:error, Error.t()}
end
