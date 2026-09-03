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
    secure: Application.compile_env(:remote_org_chart, :secure_cookies, false)
  ]

  # socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :remote_org_chart,
    gzip: Application.compile_env(:remote_org_chart, :gzip_static, false),
    only: RemoteOrgChartWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId, assign_as: :request_id
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug RemoteOrgChartWeb.Router
end
