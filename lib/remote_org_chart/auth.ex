defmodule RemoteOrgChart.Auth do
  @moduledoc """
  Public authentication service boundary for the reviewer login.
  """

  @invalid_input ""

  def credentials_version do
    {:ok, credentials} = configured_provider().credentials()
    :crypto.hash(:sha256, :erlang.term_to_binary(credentials))
  end

  def authenticated?(conn) do
    RemoteOrgChart.SecurityState.valid_session?(
      Plug.Conn.get_session(conn, :session_id),
      credentials_version()
    )
  end

  @spec authenticate(term(), term(), module()) :: :ok | {:error, :invalid_credentials}
  def authenticate(username, password, provider \\ configured_provider()) do
    case provider.credentials() do
      {:ok, %{username: configured_username, password: configured_password}}
      when is_binary(configured_username) and is_binary(configured_password) ->
        compare_credentials(
          username,
          password,
          configured_username,
          configured_password
        )

      _invalid_provider_response ->
        {:error, :invalid_credentials}
    end
  end

  defp compare_credentials(username, password, configured_username, configured_password) do
    inputs_are_strings = is_binary(username) and is_binary(password)

    submitted_username_digest = digest(credential_value(username))
    configured_username_digest = digest(configured_username)
    submitted_password_digest = digest(credential_value(password))
    configured_password_digest = digest(configured_password)

    username_matches =
      Plug.Crypto.secure_compare(
        submitted_username_digest,
        configured_username_digest
      )

    password_matches =
      Plug.Crypto.secure_compare(
        submitted_password_digest,
        configured_password_digest
      )

    if inputs_are_strings and username_matches and password_matches do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end

  defp credential_value(value) when is_binary(value), do: value
  defp credential_value(_value), do: @invalid_input
  defp digest(value), do: :crypto.hash(:sha256, value)

  defp configured_provider do
    Application.get_env(
      :remote_org_chart,
      :auth_provider,
      RemoteOrgChart.Auth.EnvironmentProvider
    )
  end
end
