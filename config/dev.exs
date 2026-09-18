import Config

config :remote_org_chart,
  remote_source: RemoteOrgChart.Remote.FixtureClient,
  remote_fixture_directory: Path.expand("../fixtures/remote", __DIR__)

# Vite runs separately; Phoenix serves the API with code reloading.
config :remote_org_chart, RemoteOrgChartWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "J6YDMmkI48PjNT8jVKYqdxmCWxzKCEPxIUnhgHboLLm8hfPWbuA4ZEqyQMFlThRi",
  watchers: []

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
