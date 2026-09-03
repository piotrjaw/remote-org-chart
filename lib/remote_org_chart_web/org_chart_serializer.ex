defmodule RemoteOrgChartWeb.OrgChartSerializer do
  @moduledoc """
  Explicitly serializes only the organization fields approved for the browser.
  """

  alias RemoteOrgChart.Hierarchy.Node
  alias RemoteOrgChart.RemoteCache.Result

  @spec to_map(Result.t()) :: map()
  def to_map(%Result{} = result) do
    chart = result.chart

    %{
      company: %{
        id: chart.company.id,
        name: chart.company.name
      },
      roots: Enum.map(chart.roots, &node_to_map/1),
      warnings: chart.warnings,
      meta: %{
        employee_count: chart.employee_count,
        root_count: chart.root_count,
        fetched_at: DateTime.to_iso8601(result.fetched_at),
        stale: result.stale
      }
    }
  end

  defp node_to_map(%Node{} = node) do
    %{
      id: node.id,
      name: node.name,
      title: node.title,
      department: summary_to_map(node.department),
      manager: summary_to_map(node.manager),
      status: node.status,
      employment_type: node.employment_type,
      employment_model: node.employment_model,
      reports: Enum.map(node.reports, &node_to_map/1)
    }
  end

  defp summary_to_map(nil), do: nil
  defp summary_to_map(summary), do: %{id: summary.id, name: summary.name}
end
