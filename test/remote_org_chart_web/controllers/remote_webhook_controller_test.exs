defmodule RemoteOrgChartWeb.RemoteWebhookControllerTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  @body ~s({"event_type":"employment.updated","employment_id":"emp_123"})
  @timestamp "1726500000000"
  @signature "23fc4e327ffd8846d2d26e201a250373518cb5feda82e8040d389d26af6e06de"

  test "invalidates the cache for an authentic Remote webhook", %{conn: conn} do
    conn = post_webhook(conn, @signature)

    assert response(conn, 204) == ""
    assert_received :cache_invalidated
  end

  test "rejects a webhook with an invalid signature without invalidating", %{conn: conn} do
    conn = post_webhook(conn, String.duplicate("0", 64))

    assert %{"error" => %{"code" => "invalid_webhook_signature"}} =
             json_response(conn, 401)

    refute_received :cache_invalidated
  end

  test "rejects a webhook with missing signature headers without invalidating", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/webhooks/remote", @body)

    assert %{"error" => %{"code" => "invalid_webhook_signature"}} =
             json_response(conn, 401)

    refute_received :cache_invalidated
  end

  test "rejects malformed JSON before parsing when the signature is missing", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/webhooks/remote", "{")

    assert %{"error" => %{"code" => "invalid_webhook_signature"}} =
             json_response(conn, 401)

    refute_received :cache_invalidated
  end

  test "rejects malformed JSON before parsing when the signature is invalid", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-remote-timestamp", @timestamp)
      |> put_req_header("x-remote-signature", String.duplicate("0", 64))
      |> post("/api/webhooks/remote", "{")

    assert %{"error" => %{"code" => "invalid_webhook_signature"}} =
             json_response(conn, 401)

    refute_received :cache_invalidated
  end

  defp post_webhook(conn, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-remote-timestamp", @timestamp)
    |> put_req_header("x-remote-signature", signature)
    |> post("/api/webhooks/remote", @body)
  end
end
