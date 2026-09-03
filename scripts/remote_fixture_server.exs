defmodule RemoteOrgChart.FixtureServer do
  use Plug.Router

  @fixture_directory Path.expand("../fixtures/remote", __DIR__)
  @company_id "00000000-0000-4000-8000-000000000001"
  @token "non-secret-smoke-token"

  plug :authenticate
  plug :match
  plug :dispatch

  get "/v1/identity/current" do
    send_fixture(conn, "identity_current.json")
  end

  get "/v1/employments/bulk" do
    conn = fetch_query_params(conn)

    with %{"company_id" => @company_id, "limit" => "100"} <- conn.query_params,
         {:ok, fixture} <- page_for_cursor(conn.query_params["cursor"]) do
      send_fixture(conn, fixture)
    else
      _invalid -> send_resp(conn, 400, "invalid pagination request")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp authenticate(conn, _options) do
    if get_req_header(conn, "authorization") == ["Bearer #{@token}"] do
      conn
    else
      conn |> send_resp(401, "unauthorized") |> halt()
    end
  end

  defp page_for_cursor(nil), do: {:ok, "employments_bulk_complex_page_1.json"}

  defp page_for_cursor("fixture-cursor-page-2"),
    do: {:ok, "employments_bulk_complex_page_2.json"}

  defp page_for_cursor("fixture-cursor-page-3"),
    do: {:ok, "employments_bulk_complex_page_3.json"}

  defp page_for_cursor(_unknown), do: :error

  defp send_fixture(conn, filename) do
    contents = File.read!(Path.join(@fixture_directory, filename))

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, contents)
  end
end

{:ok, _server} =
  Bandit.start_link(
    plug: RemoteOrgChart.FixtureServer,
    ip: {0, 0, 0, 0},
    port: 4999
  )

IO.puts("Synthetic Remote fixture server listening on http://0.0.0.0:4999")
Process.sleep(:infinity)
