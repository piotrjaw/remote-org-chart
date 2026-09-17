defmodule RemoteOrgChartWeb.Plugs.SecurityHeaders do
  @moduledoc false
  import Plug.Conn

  @production Application.compile_env(:remote_org_chart, :secure_cookies, false)
  @csp "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

  def init(options), do: Keyword.put_new(options, :production, @production)

  def call(conn, options) do
    conn =
      if String.starts_with?(conn.request_path, "/api/"),
        do: put_resp_header(conn, "cache-control", "no-store"),
        else: conn

    if options[:production] do
      conn
      |> put_resp_header("content-security-policy", @csp)
      |> put_resp_header("strict-transport-security", "max-age=31536000")
    else
      conn
    end
  end
end
