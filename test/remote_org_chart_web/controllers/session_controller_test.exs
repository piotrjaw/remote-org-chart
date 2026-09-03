defmodule RemoteOrgChartWeb.SessionControllerTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  test "bootstraps an unauthenticated session and CSRF token", %{conn: conn} do
    conn = get(conn, "/api/session")

    assert %{
             "authenticated" => false,
             "csrf_token" => csrf_token
           } = json_response(conn, 200)

    assert is_binary(csrf_token)
    assert byte_size(csrf_token) > 20
    [session_cookie | _rest] = get_resp_header(conn, "set-cookie")
    assert session_cookie =~ "HttpOnly"
    assert session_cookie =~ "SameSite=Lax"
    refute session_cookie =~ "Secure"
  end

  test "renews the session and CSRF token after valid credentials", %{conn: conn} do
    bootstrap_conn = get(conn, "/api/session")
    %{"csrf_token" => initial_csrf} = json_response(bootstrap_conn, 200)
    initial_cookie = get_resp_header(bootstrap_conn, "set-cookie")

    login_conn =
      bootstrap_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-csrf-token", initial_csrf)
      |> post(
        "/api/session",
        Jason.encode!(%{username: "reviewer", password: "test-password"})
      )

    assert %{
             "authenticated" => true,
             "csrf_token" => renewed_csrf
           } = json_response(login_conn, 200)

    assert renewed_csrf != initial_csrf
    assert get_resp_header(login_conn, "set-cookie") != initial_cookie

    session_conn =
      login_conn
      |> recycle()
      |> get("/api/session")

    assert %{"authenticated" => true} = json_response(session_conn, 200)
  end

  test "drops the authenticated session on logout", %{conn: conn} do
    login_conn = log_in(conn)
    %{"csrf_token" => csrf_token} = json_response(login_conn, 200)

    logout_conn =
      login_conn
      |> recycle()
      |> put_req_header("x-csrf-token", csrf_token)
      |> delete("/api/session")

    assert response(logout_conn, 204) == ""

    session_conn =
      logout_conn
      |> recycle()
      |> get("/api/session")

    assert %{"authenticated" => false} = json_response(session_conn, 200)
  end

  test "returns one generic error for invalid or incomplete credentials" do
    invalid_payloads = [
      %{username: "wrong", password: "test-password"},
      %{username: "reviewer", password: "wrong"},
      %{username: "reviewer"}
    ]

    Enum.each(invalid_payloads, fn payload ->
      bootstrap_conn = get(build_conn(), "/api/session")
      %{"csrf_token" => csrf_token} = json_response(bootstrap_conn, 200)

      conn =
        bootstrap_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-csrf-token", csrf_token)
        |> post("/api/session", Jason.encode!(payload))

      assert json_response(conn, 401) == %{
               "error" => %{"code" => "invalid_credentials"}
             }

      refute conn.resp_body =~ "username"
      refute conn.resp_body =~ "password"
    end)
  end

  test "rejects state-changing session requests without a CSRF token", %{conn: conn} do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> enable_csrf_protection()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/session",
        Jason.encode!(%{username: "reviewer", password: "test-password"})
      )
    end
  end

  defp enable_csrf_protection(conn) do
    %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
  end

  defp log_in(conn) do
    bootstrap_conn = get(conn, "/api/session")
    %{"csrf_token" => csrf_token} = json_response(bootstrap_conn, 200)

    bootstrap_conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-csrf-token", csrf_token)
    |> post(
      "/api/session",
      Jason.encode!(%{username: "reviewer", password: "test-password"})
    )
  end
end
