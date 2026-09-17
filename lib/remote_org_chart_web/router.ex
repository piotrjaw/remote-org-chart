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

  pipeline :spa do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/webhooks/remote", RemoteWebhookController, :create
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through :api_session

    get "/session", SessionController, :show
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through [:api_session, :authenticated]

    get "/org-chart", OrgChartController, :index
    post "/org-chart/refresh", OrgChartController, :refresh
  end

  scope "/api", RemoteOrgChartWeb do
    pipe_through :api

    match :*, "/*path", ApiNotFoundController, :show
  end

  scope "/", RemoteOrgChartWeb do
    pipe_through :spa

    get "/", SpaController, :index
    get "/*path", SpaController, :index
  end
end
