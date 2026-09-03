defmodule RemoteOrgChartWeb.OrgChartController do
  use RemoteOrgChartWeb, :controller

  require Logger

  alias RemoteOrgChart.Remote.Error
  alias RemoteOrgChartWeb.{OrgChartSerializer, RemoteErrorResponse}

  def index(conn, _params) do
    call_cache(conn, :get)
  end

  def refresh(conn, _params) do
    call_cache(conn, :refresh)
  end

  defp call_cache(conn, operation) do
    cache = Application.fetch_env!(:remote_org_chart, :remote_cache_module)
    respond(conn, apply(cache, operation, []))
  rescue
    exception ->
      Logger.error("Organization cache failed unexpectedly",
        exception_module: inspect(exception.__struct__),
        request_id: conn.assigns[:request_id]
      )

      respond(conn, {:error, %Error{kind: :internal, operation: :cache}})
  end

  defp respond(conn, {:ok, result}) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(OrgChartSerializer.to_map(result))
  end

  defp respond(conn, {:error, %Error{} = error}) do
    RemoteErrorResponse.send_response(conn, error)
  end
end
