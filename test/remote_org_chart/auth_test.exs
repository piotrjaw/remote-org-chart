defmodule RemoteOrgChart.AuthTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.Auth
  alias RemoteOrgChart.Auth.EnvironmentProvider

  defmodule ProviderStub do
    @behaviour RemoteOrgChart.Auth.Provider

    @impl true
    def credentials do
      {:ok, %{username: "reviewer", password: "correct horse battery staple"}}
    end
  end

  test "accepts only an exact username and password pair" do
    assert :ok =
             Auth.authenticate(
               "reviewer",
               "correct horse battery staple",
               ProviderStub
             )

    invalid_attempts = [
      {"wrong", "correct horse battery staple"},
      {"reviewer", "wrong"},
      {"wrong", "wrong"},
      {nil, "correct horse battery staple"},
      {"reviewer", nil}
    ]

    Enum.each(invalid_attempts, fn {username, password} ->
      assert {:error, :invalid_credentials} =
               Auth.authenticate(username, password, ProviderStub)
    end)
  end

  test "environment provider exposes only the runtime credential pair" do
    assert EnvironmentProvider.credentials() ==
             {:ok, %{username: "reviewer", password: "test-password"}}
  end
end
