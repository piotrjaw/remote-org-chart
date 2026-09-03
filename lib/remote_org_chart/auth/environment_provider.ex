defmodule RemoteOrgChart.Auth.EnvironmentProvider do
  @moduledoc """
  Reads credentials loaded from environment variables at application startup.
  """

  @behaviour RemoteOrgChart.Auth.Provider

  @impl true
  def credentials do
    {:ok, Application.fetch_env!(:remote_org_chart, :app_credentials)}
  end
end
