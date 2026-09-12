defmodule RemoteOrgChart.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.RuntimeConfig

  @valid_env %{
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "PHX_HOST" => "org-chart.example.com",
    "APP_USERNAME" => "reviewer",
    "APP_PASSWORD" => "deployment-password",
    "REMOTE_API_TOKEN" => "deployment-token",
    "REMOTE_DATA_SOURCE" => "api"
  }

  test "parses the required production configuration" do
    assert %{
             secret_key_base: secret,
             host: "org-chart.example.com",
             port: 4000,
             app_credentials: %{
               username: "reviewer",
               password: "deployment-password"
             },
             remote_api_token: "deployment-token",
             remote_cache_ttl_ms: 300_000
           } = production!(@valid_env)

    assert byte_size(secret) == 64
  end

  test "uses Render's assigned external hostname when PHX_HOST is not set" do
    env =
      @valid_env
      |> Map.delete("PHX_HOST")
      |> Map.put("RENDER_EXTERNAL_HOSTNAME", "remote-org-chart.onrender.com")

    assert %{host: "remote-org-chart.onrender.com"} = production!(env)
  end

  test "rejects every missing or blank production value without printing it" do
    required = [
      "SECRET_KEY_BASE",
      "APP_USERNAME",
      "APP_PASSWORD",
      "REMOTE_API_TOKEN",
      "REMOTE_DATA_SOURCE"
    ]

    Enum.each(required, fn variable ->
      for value <- [nil, "", "   "] do
        env =
          if value == nil,
            do: Map.delete(@valid_env, variable),
            else: Map.put(@valid_env, variable, value)

        assert_raise RuntimeError, ~r/#{variable}/, fn -> production!(env) end
      end
    end)
  end

  test "requires api mode in production without echoing the invalid value" do
    error =
      assert_raise RuntimeError, fn ->
        production!(Map.put(@valid_env, "REMOTE_DATA_SOURCE", "private-mode"))
      end

    assert Exception.message(error) =~ "REMOTE_DATA_SOURCE"
    refute Exception.message(error) =~ "private-mode"
  end

  test "parses a non-negative cache TTL" do
    assert RuntimeConfig.cache_ttl_ms(nil) == 300_000
    assert RuntimeConfig.cache_ttl_ms("0") == 0
    assert RuntimeConfig.cache_ttl_ms("42") == 42_000

    for invalid <- ["", "-1", "1.5", "seconds"] do
      assert_raise RuntimeError, ~r/REMOTE_CACHE_TTL_SECONDS/, fn ->
        RuntimeConfig.cache_ttl_ms(invalid)
      end
    end
  end

  test "parses a valid HTTP port and rejects malformed values" do
    assert RuntimeConfig.port(nil) == 4000
    assert RuntimeConfig.port("10000") == 10_000

    for invalid <- ["0", "65536", "abc", "4000x"] do
      assert_raise RuntimeError, ~r/PORT/, fn -> RuntimeConfig.port(invalid) end
    end
  end

  defp production!(env) do
    RuntimeConfig.production!(
      fn variable ->
        case Map.fetch(env, variable) do
          {:ok, value} -> value
          :error -> raise "environment variable #{variable} is missing or blank"
        end
      end,
      &Map.get(env, &1)
    )
  end
end
