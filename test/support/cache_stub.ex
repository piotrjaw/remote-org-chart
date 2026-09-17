defmodule RemoteOrgChartWeb.OrgChartControllerTest.CacheStub do
  @moduledoc false

  def get, do: result(:get)
  def refresh, do: result(:refresh)

  def invalidate do
    send(self(), :cache_invalidated)
    :ok
  end

  defp result(operation) do
    case Process.get({__MODULE__, operation}) do
      :raise -> raise "private cache failure"
      result -> result
    end
  end
end
