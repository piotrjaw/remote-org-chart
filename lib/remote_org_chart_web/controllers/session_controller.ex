defmodule RemoteOrgChartWeb.SessionController do
  use RemoteOrgChartWeb, :controller

  alias RemoteOrgChart.{Auth, SecurityState}

  def show(conn, _params) do
    json(conn, %{
      authenticated: Auth.authenticated?(conn),
      csrf_token: get_csrf_token()
    })
  end

  def create(conn, params) do
    case SecurityState.allow_login() do
      :ok ->
        authenticate(conn, params)

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "login_rate_limited"}})
    end
  end

  defp authenticate(conn, %{"username" => username, "password" => password}) do
    case Auth.authenticate(username, password) do
      :ok ->
        case SecurityState.create_session(Auth.credentials_version()) do
          {:ok, token} ->
            SecurityState.revoke_session(get_session(conn, :session_id))
            delete_csrf_token()

            conn
            |> configure_session(renew: true)
            |> clear_session()
            |> put_session(:session_id, token)
            |> json(%{authenticated: true, csrf_token: get_csrf_token()})

          {:error, :capacity} ->
            conn
            |> put_status(:service_unavailable)
            |> json(%{error: %{code: "session_unavailable"}})
        end

      {:error, :invalid_credentials} ->
        invalid_credentials(conn)
    end
  end

  defp authenticate(conn, _params), do: invalid_credentials(conn)

  def delete(conn, _params) do
    SecurityState.revoke_session(get_session(conn, :session_id))
    delete_csrf_token()

    conn
    |> configure_session(drop: true)
    |> send_resp(:no_content, "")
  end

  defp invalid_credentials(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "invalid_credentials"}})
  end
end
