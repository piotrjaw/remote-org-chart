defmodule RemoteOrgChartWeb.HealthController do
  use RemoteOrgChartWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
