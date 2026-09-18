defmodule RemoteOrgChart.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RemoteOrgChartWeb.Telemetry,
      {RemoteOrgChart.SecurityState,
       Application.get_env(:remote_org_chart, :security_state_options, [])},
      {Phoenix.PubSub, name: RemoteOrgChart.PubSub},
      {Task.Supervisor, name: RemoteOrgChart.FetchSupervisor},
      # Cache one complete, normalized organization chart in memory.
      {RemoteOrgChart.RemoteCache,
       fetcher: &RemoteOrgChart.Remote.fetch_chart/0,
       ttl_ms: Application.fetch_env!(:remote_org_chart, :remote_cache_ttl_ms)},
      RemoteOrgChartWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: RemoteOrgChart.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    RemoteOrgChartWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
