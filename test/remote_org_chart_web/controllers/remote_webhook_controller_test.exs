defmodule RemoteOrgChartWeb.RemoteWebhookControllerTest do
  use RemoteOrgChartWeb.ConnCase, async: true

  @body ~s({"event_type":"employment.updated","employment_id":"emp_123"})
  @timestamp "1726500000000"

  test "invalidates the cache for an authentic Remote webhook", %{conn: conn} do
    conn = post_webhook(conn, :valid)

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

  test "rejects old, future, and malformed signed timestamps" do
    for timestamp <- [
          "1726500000000",
          Integer.to_string(System.system_time(:millisecond) + 360_000),
          "not-a-timestamp"
        ] do
      conn = post_webhook(build_conn(), :valid, timestamp)
      assert json_response(conn, 401)
      refute_received :cache_invalidated
    end
  end

  test "acknowledges a duplicate without invalidating twice" do
    timestamp = Integer.to_string(System.system_time(:millisecond))
    body = Jason.encode!(%{id: "event-#{System.unique_integer([:positive])}"})
    assert post_webhook(build_conn(), :valid, timestamp, body) |> response(204) == ""
    assert_received :cache_invalidated
    assert post_webhook(build_conn(), :valid, timestamp, body) |> response(204) == ""
    refute_received :cache_invalidated
  end

  test "a routing rejection does not consume an authentic delivery" do
    timestamp = Integer.to_string(System.system_time(:millisecond))
    body = Jason.encode!(%{id: "negotiation-#{System.unique_integer([:positive])}"})

    assert_raise Phoenix.NotAcceptableError, fn ->
      build_conn()
      |> put_req_header("accept", "text/html")
      |> post_webhook(:valid, timestamp, body)
    end

    refute_received :cache_invalidated
    assert post_webhook(build_conn(), :valid, timestamp, body) |> response(204) == ""
    assert_received :cache_invalidated
  end

  defp post_webhook(
         conn,
         signature,
         timestamp \\ Integer.to_string(System.system_time(:millisecond)),
         body \\ @body
       ) do
    signature =
      if signature == :valid do
        :crypto.mac(:hmac, :sha256, "test-webhook-signing-key", body <> ":" <> timestamp)
        |> Base.encode16(case: :lower)
      else
        signature
      end

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-remote-timestamp", timestamp)
    |> put_req_header("x-remote-signature", signature)
    |> post("/api/webhooks/remote", body)
  end
end
