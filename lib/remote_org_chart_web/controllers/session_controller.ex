defmodule RemoteOrgChartWeb.SessionController do
  use RemoteOrgChartWeb, :controller

  alias RemoteOrgChart.Auth

  def show(conn, _params) do
    json(conn, %{
      authenticated: get_session(conn, :authenticated) == true,
      csrf_token: get_csrf_token()
    })
  end

  def create(conn, %{"username" => username, "password" => password}) do
    case Auth.authenticate(username, password) do
      :ok ->
        delete_csrf_token()

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:authenticated, true)
        |> json(%{authenticated: true, csrf_token: get_csrf_token()})

      {:error, :invalid_credentials} ->
        invalid_credentials(conn)
    end
  end

  def create(conn, _params), do: invalid_credentials(conn)

  def delete(conn, _params) do
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
