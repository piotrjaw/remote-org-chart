defmodule RemoteOrgChartWeb.RemoteWebhookController do
  use RemoteOrgChartWeb, :controller

  def create(%{assigns: %{remote_webhook_verified: true}} = conn, _params) do
    cache = Application.fetch_env!(:remote_org_chart, :remote_cache_module)
    :ok = cache.invalidate()
    send_resp(conn, :no_content, "")
  end

  def create(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "invalid_webhook_signature"}})
  end
end
