# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :remote_org_chart,
  remote_cache_ttl_ms: 300_000,
  auth_provider: RemoteOrgChart.Auth.EnvironmentProvider,
  remote_cache_module: RemoteOrgChart.RemoteCache,
  secure_cookies: false

# Configures the endpoint
config :remote_org_chart, RemoteOrgChartWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: RemoteOrgChartWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RemoteOrgChart.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :remote_duration_ms,
    :remote_page_count,
    :remote_employee_count,
    :remote_warning_count,
    :remote_error_kind,
    :remote_operation,
    :remote_exception,
    :exception_module
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
