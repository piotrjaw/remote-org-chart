defmodule RemoteOrgChart.Remote do
  @moduledoc """
  Public boundary for acquiring and constructing an organization chart.
  """

  require Logger

  alias RemoteOrgChart.Hierarchy
  alias RemoteOrgChart.Remote.{Error, Mapper}

  @spec fetch_chart(keyword()) :: {:ok, Hierarchy.Chart.t()} | {:error, Error.t()}
  def fetch_chart(options \\ []) do
    source =
      Keyword.get(
        options,
        :source,
        Application.get_env(:remote_org_chart, :remote_source)
      )

    source_options = Keyword.get(options, :source_options, [])
    started_at = System.monotonic_time(:millisecond)

    result =
      with source when is_atom(source) <- source,
           {:ok, %{identity: identity, employments: employments, page_count: page_count}} <-
             source.fetch(source_options),
           {:ok, snapshot} <- Mapper.map(identity, employments) do
        chart = Hierarchy.build(snapshot)
        {:ok, chart, page_count}
      else
        {:error, %Error{} = error} -> {:error, error}
        _invalid -> {:error, Error.invalid_response(:source)}
      end

    log_result(result, started_at)

    case result do
      {:ok, chart, _page_count} -> {:ok, chart}
      {:error, error} -> {:error, error}
    end
  rescue
    exception ->
      Logger.error("Remote snapshot failed unexpectedly",
        remote_exception: inspect(exception.__struct__)
      )

      {:error, %Error{kind: :internal, operation: :source}}
  end

  defp log_result({:ok, chart, page_count}, started_at) do
    Logger.info("Remote snapshot loaded",
      remote_duration_ms: elapsed_ms(started_at),
      remote_page_count: page_count,
      remote_employee_count: chart.employee_count,
      remote_warning_count: length(chart.warnings)
    )
  end

  defp log_result({:error, error}, started_at) do
    Logger.warning("Remote snapshot failed",
      remote_duration_ms: elapsed_ms(started_at),
      remote_error_kind: error.kind,
      remote_operation: error.operation
    )
  end

  defp elapsed_ms(started_at), do: System.monotonic_time(:millisecond) - started_at
end
