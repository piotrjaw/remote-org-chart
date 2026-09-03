import Config

config :remote_org_chart,
  secure_cookies: true,
  gzip_static: true

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
