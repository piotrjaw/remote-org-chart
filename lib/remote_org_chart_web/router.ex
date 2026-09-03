defmodule RemoteOrgChartWeb.Router do
  use RemoteOrgChartWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through :api
  end
end
