defmodule RemoteOrgChartWeb.SpaController do
  use RemoteOrgChartWeb, :controller

  def index(conn, _params) do
    index_path =
      Application.get_env(
        :remote_org_chart,
        :spa_index_path,
        Application.app_dir(:remote_org_chart, "priv/static/index.html")
      )

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, index_path)
  end
end
