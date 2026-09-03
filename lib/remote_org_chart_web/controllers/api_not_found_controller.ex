defmodule RemoteOrgChartWeb.ApiNotFoundController do
  use RemoteOrgChartWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: %{code: "not_found"}})
  end
end
