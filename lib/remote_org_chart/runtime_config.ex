defmodule RemoteOrgChart.RuntimeConfig do
  @moduledoc false

  @default_cache_ttl_ms 300_000
  @default_port 4000

  @spec production!((String.t() -> String.t()), (String.t() -> String.t() | nil)) :: map()
  def production!(fetch_env!, get_env) do
    source = fetch_env! |> required!("REMOTE_DATA_SOURCE") |> String.trim()

    if source != "api" do
      raise "REMOTE_DATA_SOURCE must be api in production"
    end

    secret_key_base = required!(fetch_env!, "SECRET_KEY_BASE")

    if byte_size(secret_key_base) < 64 do
      raise "SECRET_KEY_BASE must contain at least 64 bytes"
    end

    %{
      secret_key_base: secret_key_base,
      host: deployment_host!(get_env),
      port: get_env.("PORT") |> port(),
      app_credentials: %{
        username: fetch_env! |> required!("APP_USERNAME") |> String.trim(),
        password: required!(fetch_env!, "APP_PASSWORD")
      },
      remote_api_token: required!(fetch_env!, "REMOTE_API_TOKEN"),
      remote_api_base_url:
        optional_nonblank(
          get_env.("REMOTE_API_BASE_URL"),
          "REMOTE_API_BASE_URL",
          "https://gateway.remote-sandbox.com"
        ),
      remote_cache_ttl_ms: get_env.("REMOTE_CACHE_TTL_SECONDS") |> cache_ttl_ms()
    }
  end

  @spec required!((String.t() -> String.t()), String.t()) :: String.t()
  def required!(fetch_env!, variable) do
    case fetch_env!.(variable) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          raise "environment variable #{variable} is missing or blank"
        else
          value
        end

      _other ->
        raise "environment variable #{variable} is missing or blank"
    end
  rescue
    _error -> raise "environment variable #{variable} is missing or blank"
  end

  @spec cache_ttl_ms(String.t() | nil) :: non_neg_integer()
  def cache_ttl_ms(nil), do: @default_cache_ttl_ms

  def cache_ttl_ms(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds * 1_000
      _invalid -> raise "REMOTE_CACHE_TTL_SECONDS must be a non-negative integer"
    end
  end

  def cache_ttl_ms(_value) do
    raise "REMOTE_CACHE_TTL_SECONDS must be a non-negative integer"
  end

  @spec port(String.t() | nil) :: pos_integer()
  def port(nil), do: @default_port

  def port(value) when is_binary(value) do
    case Integer.parse(value) do
      {port, ""} when port in 1..65_535 -> port
      _invalid -> raise "PORT must be an integer between 1 and 65535"
    end
  end

  def port(_value), do: raise("PORT must be an integer between 1 and 65535")

  defp deployment_host!(get_env) do
    case get_env.("PHX_HOST") do
      nil -> get_env |> required!("RENDER_EXTERNAL_HOSTNAME") |> String.trim()
      host -> fn _variable -> host end |> required!("PHX_HOST") |> String.trim()
    end
  end

  defp optional_nonblank(nil, _variable, default), do: default

  defp optional_nonblank(value, variable, _default) when is_binary(value) do
    case String.trim(value) do
      "" -> raise "#{variable} must not be blank when set"
      trimmed -> trimmed
    end
  end
end
