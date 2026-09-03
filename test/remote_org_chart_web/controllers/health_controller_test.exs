defmodule RemoteOrgChartWeb.HealthControllerTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  test "reports health without requiring a session", %{conn: conn} do
    conn = get(conn, "/api/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "set-cookie") == []
  end
end
