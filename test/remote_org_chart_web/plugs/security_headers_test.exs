defmodule RemoteOrgChartWeb.Plugs.SecurityHeadersTest do
  use RemoteOrgChartWeb.ConnCase, async: true
  alias RemoteOrgChartWeb.Plugs.SecurityHeaders

  test "production CSP restricts scripts and connections without unsafe-inline" do
    conn = build_conn() |> SecurityHeaders.call(SecurityHeaders.init(production: true))
    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "script-src 'self'"
    assert csp =~ "connect-src 'self'"
    assert csp =~ "frame-ancestors 'none'"
    refute csp =~ "unsafe-inline"
    assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
  end

  test "all session responses prevent caching" do
    conn = get(build_conn(), "/api/session")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end
