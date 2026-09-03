import Config

alias RemoteOrgChart.RuntimeConfig

if config_env() == :prod do
  runtime = RuntimeConfig.production!(&System.fetch_env!/1, &System.get_env/1)

  config :remote_org_chart,
    app_credentials: runtime.app_credentials,
    remote_source: RemoteOrgChart.Remote.Client,
    remote_api_token: runtime.remote_api_token,
    remote_api_base_url: runtime.remote_api_base_url,
    remote_cache_ttl_ms: runtime.remote_cache_ttl_ms

  config :remote_org_chart, RemoteOrgChartWeb.Endpoint,
    server: true,
    url: [host: runtime.host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: runtime.port
    ],
    secret_key_base: runtime.secret_key_base
else
  config :remote_org_chart,
    remote_api_base_url:
      System.get_env("REMOTE_API_BASE_URL", "https://gateway.remote-sandbox.com"),
    remote_cache_ttl_ms:
      System.get_env("REMOTE_CACHE_TTL_SECONDS") |> RuntimeConfig.cache_ttl_ms()

  if config_env() != :test do
    config :remote_org_chart,
      app_credentials: %{
        username: RuntimeConfig.required!(&System.fetch_env!/1, "APP_USERNAME") |> String.trim(),
        password: RuntimeConfig.required!(&System.fetch_env!/1, "APP_PASSWORD")
      }

    case System.get_env("REMOTE_DATA_SOURCE") do
      nil ->
        :ok

      "fixture" ->
        config :remote_org_chart, remote_source: RemoteOrgChart.Remote.FixtureClient

      "api" ->
        config :remote_org_chart,
          remote_source: RemoteOrgChart.Remote.Client,
          remote_api_token: RuntimeConfig.required!(&System.fetch_env!/1, "REMOTE_API_TOKEN")

      _invalid ->
        raise "REMOTE_DATA_SOURCE must be either api or fixture"
    end
  end
end
