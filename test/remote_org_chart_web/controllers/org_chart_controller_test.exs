defmodule RemoteOrgChartWeb.OrgChartControllerTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  alias RemoteOrgChart.Hierarchy.{Chart, Node}
  alias RemoteOrgChart.Remote.{Company, Error}
  alias RemoteOrgChart.RemoteCache.Result
  alias RemoteOrgChartWeb.OrgChartControllerTest.CacheStub

  test "returns the normalized recursive chart with cache metadata", %{conn: conn} do
    child = node("child", "Child", [])
    root = node("root", "Root", [child])

    result = %Result{
      chart: %Chart{
        company: %Company{id: "company", name: "Acme Sandbox Corp"},
        roots: [root],
        warnings: [%{code: "external_manager", employment_id: "root"}],
        employee_count: 2,
        root_count: 1
      },
      fetched_at: ~U[2026-09-03 12:00:00Z],
      stale: false
    }

    Process.put({CacheStub, :get}, {:ok, result})

    conn =
      conn
      |> init_test_session(authenticated_session())
      |> get("/api/org-chart")

    assert %{
             "company" => %{
               "id" => "company",
               "name" => "Acme Sandbox Corp"
             },
             "roots" => [
               %{
                 "id" => "root",
                 "name" => "Root",
                 "reports" => [%{"id" => "child", "name" => "Child"}]
               }
             ],
             "warnings" => [
               %{"code" => "external_manager", "employment_id" => "root"}
             ],
             "meta" => %{
               "employee_count" => 2,
               "root_count" => 1,
               "fetched_at" => "2026-09-03T12:00:00Z",
               "stale" => false
             }
           } = json_response(conn, 200)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "forces a refresh with an authenticated CSRF-protected request", %{conn: conn} do
    result = %Result{
      chart: %Chart{
        company: %Company{id: "company", name: "Refreshed Company"},
        roots: [],
        warnings: [],
        employee_count: 0,
        root_count: 0
      },
      fetched_at: ~U[2026-09-03 12:30:00Z],
      stale: false
    }

    Process.put({CacheStub, :refresh}, {:ok, result})
    login_conn = log_in_with_csrf(conn)
    %{"csrf_token" => csrf_token} = json_response(login_conn, 200)

    refresh_conn =
      login_conn
      |> recycle()
      |> enable_csrf_protection()
      |> put_req_header("x-csrf-token", csrf_token)
      |> post("/api/org-chart/refresh")

    assert %{
             "company" => %{"name" => "Refreshed Company"},
             "meta" => %{"employee_count" => 0}
           } = json_response(refresh_conn, 200)

    assert get_resp_header(refresh_conn, "cache-control") == ["no-store"]
  end

  test "requires authentication before consulting the cache", %{conn: conn} do
    Process.delete({CacheStub, :get})

    conn = get(conn, "/api/org-chart")

    assert json_response(conn, 401) == %{
             "error" => %{"code" => "authentication_required"}
           }

    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "maps typed Remote failures to safe HTTP responses" do
    cases = [
      {Error.authentication(:http), 502, "remote_authentication_failed"},
      {Error.temporary(:http, 45), 503, "remote_temporarily_unavailable"},
      {Error.invalid_response(:http), 502, "invalid_remote_response"},
      {%Error{kind: :internal, operation: :source}, 500, "internal_error"}
    ]

    Enum.each(cases, fn {error, status, code} ->
      Process.put({CacheStub, :get}, {:error, error})

      conn =
        build_conn()
        |> put_req_header("x-request-id", "test-request-id-00000001")
        |> init_test_session(authenticated_session())
        |> get("/api/org-chart")

      assert %{"error" => response_error} = json_response(conn, status)
      assert response_error["code"] == code
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      if code == "internal_error" do
        assert response_error["request_id"] == "test-request-id-00000001"
      else
        refute Map.has_key?(response_error, "request_id")
      end

      if error.retry_after do
        assert get_resp_header(conn, "retry-after") == [Integer.to_string(error.retry_after)]
      else
        assert get_resp_header(conn, "retry-after") == []
      end

      refute conn.resp_body =~ "source"
      refute conn.resp_body =~ "upstream"
    end)
  end

  test "rejects refresh when the CSRF header is missing", %{conn: conn} do
    login_conn = log_in_with_csrf(conn)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      login_conn
      |> recycle()
      |> enable_csrf_protection()
      |> post("/api/org-chart/refresh")
    end
  end

  test "turns an unexpected cache failure into a safe request-linked 500" do
    Process.put({CacheStub, :get}, :raise)

    conn =
      build_conn()
      |> put_req_header("x-request-id", "test-request-id-00000002")
      |> init_test_session(authenticated_session())
      |> get("/api/org-chart")

    assert json_response(conn, 500) == %{
             "error" => %{
               "code" => "internal_error",
               "request_id" => "test-request-id-00000002"
             }
           }

    refute conn.resp_body =~ "private cache failure"
  end

  defp node(id, name, reports) do
    %Node{
      id: id,
      name: name,
      title: "Engineer",
      department: %{id: "department", name: "Engineering"},
      manager: nil,
      status: "active",
      employment_type: "employee",
      employment_model: "eor",
      reports: reports
    }
  end

  defp log_in_with_csrf(conn) do
    bootstrap_conn =
      conn
      |> enable_csrf_protection()
      |> get("/api/session")

    %{"csrf_token" => csrf_token} = json_response(bootstrap_conn, 200)

    bootstrap_conn
    |> recycle()
    |> enable_csrf_protection()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-csrf-token", csrf_token)
    |> post(
      "/api/session",
      Jason.encode!(%{username: "reviewer", password: "test-password"})
    )
  end

  defp enable_csrf_protection(conn) do
    %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}
  end
end
