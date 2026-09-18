defmodule RemoteOrgChartWeb.ErrorJSON do
  # Framework errors expose only the standard HTTP status description.
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
