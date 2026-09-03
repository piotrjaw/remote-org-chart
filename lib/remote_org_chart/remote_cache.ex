defmodule RemoteOrgChart.RemoteCache do
  @moduledoc """
  A one-key in-memory cache for complete normalized organization charts.
  """

  use GenServer

  alias RemoteOrgChart.Remote.Error
  alias RemoteOrgChart.RemoteCache.Result

  @type clock_value :: %{monotonic_ms: integer(), utc: DateTime.t()}

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, options, name: name)
    else
      GenServer.start_link(__MODULE__, options)
    end
  end

  @spec get(GenServer.server()) :: {:ok, Result.t()} | {:error, Error.t()}
  def get(server \\ __MODULE__), do: GenServer.call(server, :get)

  @spec refresh(GenServer.server()) :: {:ok, Result.t()} | {:error, Error.t()}
  def refresh(server \\ __MODULE__), do: GenServer.call(server, :refresh)

  @impl true
  def init(options) do
    {:ok,
     %{
       value: nil,
       fetched_at_ms: nil,
       ttl_ms: Keyword.fetch!(options, :ttl_ms),
       fetcher: Keyword.fetch!(options, :fetcher),
       now: Keyword.get(options, :now, &current_time/0)
     }}
  end

  @impl true
  def handle_call(:get, _from, state) do
    current_time = state.now.()

    if fresh?(state, current_time.monotonic_ms) do
      {:reply, {:ok, %{state.value | stale: false}}, state}
    else
      fetch(state, current_time)
    end
  end

  def handle_call(:refresh, _from, state) do
    fetch(state, state.now.())
  end

  defp fresh?(%{value: nil}, _current_ms), do: false

  defp fresh?(state, current_ms) do
    current_ms - state.fetched_at_ms < state.ttl_ms
  end

  defp fetch(state, current_time) do
    case state.fetcher.() do
      {:ok, chart} ->
        result = %Result{chart: chart, fetched_at: current_time.utc, stale: false}

        new_state = %{
          state
          | value: result,
            fetched_at_ms: current_time.monotonic_ms
        }

        {:reply, {:ok, result}, new_state}

      {:error, %Error{kind: :temporary}} when not is_nil(state.value) ->
        {:reply, {:ok, %{state.value | stale: true}}, state}

      {:error, %Error{} = error} ->
        {:reply, {:error, error}, state}
    end
  end

  defp current_time do
    %{
      monotonic_ms: System.monotonic_time(:millisecond),
      utc: DateTime.utc_now()
    }
  end
end
