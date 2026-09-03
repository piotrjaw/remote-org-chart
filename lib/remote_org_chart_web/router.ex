defmodule RemoteOrgChartWeb.Router do
  use RemoteOrgChartWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_session do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug RemoteOrgChartWeb.Plugs.RequireAuth
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through :api
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through :api_session

    get "/session", SessionController, :show
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end
end
