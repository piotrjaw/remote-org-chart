defmodule RemoteOrgChartWeb.SpaControllerTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  test "serves the SPA entry point at the root", %{conn: conn} do
    conn = get(conn, "/")

    assert html_response(conn, 200) =~ ~s(<div id="root"></div>)
  end

  test "serves the SPA entry point for client-side routes", %{conn: conn} do
    conn = get(conn, "/people/employment-123")

    assert html_response(conn, 200) =~ ~s(<div id="root"></div>)
  end

  test "keeps unknown API routes as JSON 404 responses", %{conn: conn} do
    conn = get(conn, "/api/unknown")

    assert json_response(conn, 404) == %{
             "error" => %{"code" => "not_found"}
           }
  end
end
