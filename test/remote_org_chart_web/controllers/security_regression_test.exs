defmodule RemoteOrgChartWeb.SecurityRegressionTest do
  use RemoteOrgChartWeb.ConnCase, async: false
  alias RemoteOrgChart.SecurityState

  setup do
    original = :sys.get_state(SecurityState)
    credentials = Application.fetch_env!(:remote_org_chart, :app_credentials)
    :sys.replace_state(SecurityState, fn state -> %{state | login: nil, login_limit: 2} end)

    on_exit(fn ->
      :sys.replace_state(SecurityState, fn _ -> original end)
      Application.put_env(:remote_org_chart, :app_credentials, credentials)
    end)

    :ok
  end

  test "login endpoint throttles even valid credentials and forged forwarding headers" do
    for _ <- 1..2 do
      assert attempt("wrong") |> json_response(401)
    end

    conn = attempt("test-password")
    assert %{"error" => %{"code" => "login_rate_limited"}} = json_response(conn, 429)
    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) in 1..60
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert conn
           |> recycle()
           |> get("/api/session")
           |> json_response(200)
           |> Map.fetch!("authenticated") == false
  end

  test "credential changes invalidate existing cookies and protected routes" do
    login = attempt("test-password")
    assert json_response(login, 200)["authenticated"]

    Application.put_env(:remote_org_chart, :app_credentials, %{
      username: "reviewer",
      password: "rotated"
    })

    assert login
           |> recycle()
           |> get("/api/session")
           |> json_response(200)
           |> Map.fetch!("authenticated") == false

    assert login |> recycle() |> get("/api/org-chart") |> json_response(401)
  end

  defp attempt(password) do
    bootstrap = get(build_conn(), "/api/session")
    csrf = json_response(bootstrap, 200)["csrf_token"]

    bootstrap
    |> recycle()
    |> put_req_header("x-csrf-token", csrf)
    |> put_req_header("x-forwarded-for", "#{System.unique_integer([:positive])}")
    |> post("/api/session", %{username: "reviewer", password: password})
  end
end
