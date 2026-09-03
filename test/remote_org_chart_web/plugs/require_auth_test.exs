defmodule RemoteOrgChartWeb.Plugs.RequireAuthTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  alias RemoteOrgChartWeb.Plugs.RequireAuth

  test "halts unauthenticated API requests with a JSON 401", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> RequireAuth.call([])

    assert conn.halted
    assert conn.status == 401

    assert Jason.decode!(conn.resp_body) == %{
             "error" => %{"code" => "authentication_required"}
           }
  end

  test "allows authenticated API requests to continue", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{authenticated: true})
      |> RequireAuth.call([])

    refute conn.halted
    assert conn.status == nil
  end
end
