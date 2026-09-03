defmodule RemoteOrgChartWeb.Plugs.RequireAuth do
  @moduledoc """
  Requires the application-level reviewer session for protected JSON routes.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    if get_session(conn, :authenticated) == true do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.json(%{
        error: %{code: "authentication_required"}
      })
      |> halt()
    end
  end
end
