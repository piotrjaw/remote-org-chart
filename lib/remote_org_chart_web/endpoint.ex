defmodule RemoteOrgChartWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :remote_org_chart

  # The reviewer session is stored in an encrypted and signed cookie.
  @session_options [
    store: :cookie,
    key: "_remote_org_chart_key",
    signing_salt: "CY3th7z0",
    encryption_salt: "7Yti2cGC",
    same_site: "Lax",
    http_only: true,
    max_age: 8 * 60 * 60,
    secure: Application.compile_env(:remote_org_chart, :secure_cookies, false)
  ]

  # Apply security headers to static assets as well as controller responses.
  plug RemoteOrgChartWeb.Plugs.SecurityHeaders

  plug Plug.Static,
    at: "/",
    from: :remote_org_chart,
    gzip: Application.compile_env(:remote_org_chart, :gzip_static, false),
    only: RemoteOrgChartWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId, assign_as: :request_id
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug RemoteOrgChartWeb.RemoteWebhookAuthentication

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug RemoteOrgChartWeb.Router
end
