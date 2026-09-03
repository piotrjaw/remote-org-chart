defmodule RemoteOrgChart.Remote.ClientTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.Fixture
  alias RemoteOrgChart.Remote.Client

  test "authenticates and traverses every bulk-employment cursor" do
    request =
      Req.new(
        base_url: "https://remote.test",
        auth: {:bearer, "test-token"},
        plug: {Req.Test, __MODULE__},
        retry: false
      )

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-token"]
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/v1/identity/current" ->
          Req.Test.json(conn, Fixture.read_json!("identity_current.json"))

        "/v1/employments/bulk" ->
          assert conn.query_params["company_id"] ==
                   "00000000-0000-4000-8000-000000000001"

          assert conn.query_params["limit"] == "100"

          filename =
            case conn.query_params["cursor"] do
              nil -> "employments_bulk_complex_page_1.json"
              "fixture-cursor-page-2" -> "employments_bulk_complex_page_2.json"
              "fixture-cursor-page-3" -> "employments_bulk_complex_page_3.json"
            end

          Req.Test.json(conn, Fixture.read_json!(filename))
      end
    end)

    assert {:ok, result} = Client.fetch(req: request)
    assert result.identity == Fixture.read_json!("identity_current.json")
    assert result.page_count == 3
    assert length(result.employments) == 30
    assert hd(result.employments)["id"] == "10000000-0000-4000-8000-000000000001"
    assert List.last(result.employments)["id"] == "10000000-0000-4000-8000-000000000030"
  end

  test "classifies Remote 401 and 403 responses as authentication failures" do
    Enum.each([401, 403], fn status ->
      request =
        request_for(fn conn ->
          conn
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(%{"message" => "upstream details are private"})
        end)

      assert {:error, error} = Client.fetch(req: request)
      assert error.kind == :authentication
      assert error.retry_after == nil
    end)
  end

  test "classifies rate limits as temporary and retains only a bounded Retry-After" do
    Enum.each(
      [{"45", 45}, {"301", nil}, {"tomorrow", nil}, {"-1", nil}],
      fn {header, expected_retry_after} ->
        request =
          request_for(fn conn ->
            conn
            |> Plug.Conn.put_resp_header("retry-after", header)
            |> Plug.Conn.put_status(429)
            |> Req.Test.json(%{"message" => "private"})
          end)

        assert {:error, error} = Client.fetch(req: request)
        assert error.kind == :temporary
        assert error.retry_after == expected_retry_after
      end
    )
  end

  test "classifies upstream server errors and transport timeouts as temporary" do
    server_error_request =
      request_for(fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"message" => "private"})
      end)

    timeout_request =
      request_for(fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

    for request <- [server_error_request, timeout_request] do
      assert {:error, error} = Client.fetch(req: request)
      assert error.kind == :temporary
      assert error.retry_after == nil
    end
  end

  test "rejects a repeated pagination cursor before another request loop" do
    counter_key = {__MODULE__, make_ref()}
    Process.put(counter_key, 0)

    request =
      request_for(fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.request_path do
          "/v1/identity/current" ->
            Req.Test.json(conn, Fixture.read_json!("identity_current.json"))

          "/v1/employments/bulk" ->
            count = Process.get(counter_key) + 1
            Process.put(counter_key, count)

            if count <= 2 do
              Req.Test.json(conn, %{"data" => [], "next_cursor" => "same-cursor"})
            else
              conn
              |> Plug.Conn.put_status(503)
              |> Req.Test.json(%{"message" => "loop guard"})
            end
        end
      end)

    assert {:error, error} = Client.fetch(req: request)
    assert error.kind == :invalid_response
    assert error.operation == :pagination
    assert Process.get(counter_key) == 2
  end

  test "rejects malformed identity and employment response shapes" do
    invalid_identity_request =
      request_for(fn conn ->
        Req.Test.json(conn, %{"data" => %{"company" => %{"id" => "   "}}})
      end)

    invalid_employments_request =
      request_for(fn conn ->
        case conn.request_path do
          "/v1/identity/current" ->
            Req.Test.json(conn, Fixture.read_json!("identity_current.json"))

          "/v1/employments/bulk" ->
            Req.Test.json(conn, %{"data" => "not-a-list", "next_cursor" => nil})
        end
      end)

    assert {:error, identity_error} = Client.fetch(req: invalid_identity_request)
    assert identity_error.kind == :invalid_response
    assert identity_error.operation == :identity

    assert {:error, employments_error} = Client.fetch(req: invalid_employments_request)
    assert employments_error.kind == :invalid_response
    assert employments_error.operation == :employments
  end

  test "rejects invalid JSON without exposing the response body" do
    request =
      request_for(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, "{not-json")
      end)

    assert {:error, error} = Client.fetch(req: request)
    assert error.kind == :invalid_response
    refute Map.has_key?(Map.from_struct(error), :response_body)
  end

  test "discards accumulated pages when a later page fails" do
    request =
      request_for(fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case {conn.request_path, conn.query_params["cursor"]} do
          {"/v1/identity/current", _cursor} ->
            Req.Test.json(conn, Fixture.read_json!("identity_current.json"))

          {"/v1/employments/bulk", nil} ->
            Req.Test.json(conn, %{
              "data" => [hd(Fixture.complex_employment_pages!() |> hd())],
              "next_cursor" => "second-page"
            })

          {"/v1/employments/bulk", "second-page"} ->
            conn
            |> Plug.Conn.put_status(503)
            |> Req.Test.json(%{"message" => "private upstream failure"})
        end
      end)

    assert {:error, error} = Client.fetch(req: request)
    assert error.kind == :temporary
    refute Map.has_key?(Map.from_struct(error), :employments)
    refute Map.has_key?(Map.from_struct(error), :response_body)
  end

  defp request_for(stub) do
    name = {__MODULE__, make_ref()}
    Req.Test.stub(name, stub)

    Req.new(
      base_url: "https://remote.test",
      auth: {:bearer, "test-token"},
      plug: {Req.Test, name},
      retry: false
    )
  end
end
