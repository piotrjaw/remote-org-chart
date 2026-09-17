import Config

config :remote_org_chart,
  remote_source: RemoteOrgChart.Remote.FixtureClient,
  remote_fixture_directory: Path.expand("../fixtures/remote", __DIR__),
  app_credentials: %{username: "reviewer", password: "test-password"},
  remote_webhook_signing_key: "test-webhook-signing-key",
  remote_cache_module: RemoteOrgChartWeb.OrgChartControllerTest.CacheStub,
  spa_index_path: Path.expand("../assets/index.html", __DIR__)

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :remote_org_chart, RemoteOrgChartWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9+GqQg1iKJi+e2Nnllimu4Aq4AtbA0Kb1c8V8B1Hu0W79TLS4hvWz48Eqb0ZukAB",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
