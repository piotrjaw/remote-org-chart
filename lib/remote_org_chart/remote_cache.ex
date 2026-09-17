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
  def get(server \\ __MODULE__), do: call(server, :get)

  @spec refresh(GenServer.server()) :: {:ok, Result.t()} | {:error, Error.t()}
  def refresh(server \\ __MODULE__), do: call(server, :refresh)

  defp call(server, operation) do
    GenServer.call(server, operation, 25_000)
  catch
    :exit, {:timeout, _} -> {:error, Error.temporary(:cache)}
    :exit, {:noproc, _} -> {:error, Error.temporary(:cache)}
  end

  @spec invalidate(GenServer.server()) :: :ok
  def invalidate(server \\ __MODULE__), do: GenServer.cast(server, :invalidate)

  @impl true
  def init(options) do
    {:ok,
     %{
       value: nil,
       fetched_at_ms: nil,
       refresh_after_ms: nil,
       retry_after_ms: nil,
       last_error: nil,
       latest_result: nil,
       manual_until_ms: nil,
       refresh_cooldown_ms: Keyword.get(options, :refresh_cooldown_ms, 30_000),
       fetch_timeout_ms: Keyword.get(options, :fetch_timeout_ms, 20_000),
       ttl_ms: Keyword.fetch!(options, :ttl_ms),
       invalidation_debounce_ms: Keyword.get(options, :invalidation_debounce_ms, 2_000),
       retry_cooldown_ms: Keyword.get(options, :retry_cooldown_ms, 30_000),
       fetcher: Keyword.fetch!(options, :fetcher),
       now: Keyword.get(options, :now, &current_time/0)
     }}
  end

  @impl true
  def handle_call(:get, _from, state) do
    current_time = state.now.()

    cond do
      retrying?(state, current_time.monotonic_ms) ->
        {:reply, fallback(state, state.last_error), state}

      fresh?(state, current_time.monotonic_ms) ->
        {:reply, {:ok, %{state.value | stale: false}}, state}

      true ->
        fetch(state, current_time)
    end
  end

  def handle_call(:refresh, _from, state) do
    current_time = state.now.()

    cond do
      retrying?(state, current_time.monotonic_ms) ->
        {:reply, fallback(state, state.last_error), state}

      is_integer(state.manual_until_ms) and current_time.monotonic_ms < state.manual_until_ms ->
        {:reply, state.latest_result, state}

      true ->
        {:reply, result, updated} = fetch(state, current_time)

        {:reply, result,
         %{
           updated
           | latest_result: result,
             manual_until_ms: state.now.().monotonic_ms + state.refresh_cooldown_ms
         }}
    end
  end

  @impl true
  def handle_cast(:invalidate, state) do
    refresh_after_ms = state.now.().monotonic_ms + state.invalidation_debounce_ms
    {:noreply, %{state | refresh_after_ms: refresh_after_ms}}
  end

  defp fresh?(%{value: nil}, _current_ms), do: false

  defp fresh?(%{refresh_after_ms: refresh_after_ms} = state, current_ms)
       when is_integer(refresh_after_ms) do
    current_ms < refresh_after_ms and ttl_fresh?(state, current_ms)
  end

  defp fresh?(state, current_ms), do: ttl_fresh?(state, current_ms)

  defp ttl_fresh?(state, current_ms) do
    current_ms - state.fetched_at_ms < state.ttl_ms
  end

  defp retrying?(%{retry_after_ms: retry_after_ms}, current_ms)
       when is_integer(retry_after_ms) do
    current_ms < retry_after_ms
  end

  defp retrying?(_state, _current_ms), do: false

  defp fetch(state, current_time) do
    {:reply, result, updated} = perform_fetch(state, current_time)
    {:reply, result, %{updated | latest_result: result}}
  end

  defp perform_fetch(state, current_time) do
    task = Task.Supervisor.async_nolink(RemoteOrgChart.FetchSupervisor, state.fetcher)
    outcome = Task.yield(task, state.fetch_timeout_ms) || Task.shutdown(task, :brutal_kill)

    result =
      case outcome do
        {:ok, result} -> result
        nil -> {:error, Error.temporary(:cache)}
        {:exit, _reason} -> {:error, %Error{kind: :internal, operation: :cache}}
      end

    case result do
      {:ok, chart} ->
        result = %Result{chart: chart, fetched_at: current_time.utc, stale: false}

        new_state = %{
          state
          | value: result,
            fetched_at_ms: current_time.monotonic_ms,
            refresh_after_ms: nil,
            retry_after_ms: nil,
            last_error: nil
        }

        {:reply, {:ok, result}, new_state}

      {:error, %Error{kind: :temporary} = error} ->
        finished_ms = state.now.().monotonic_ms
        cooldown_ms = max(state.retry_cooldown_ms, (error.retry_after || 0) * 1_000)

        new_state = %{
          state
          | retry_after_ms: finished_ms + cooldown_ms,
            refresh_after_ms: finished_ms,
            last_error: error
        }

        {:reply, fallback(state, error), new_state}

      {:error, %Error{} = error} ->
        # Persistent failures must back off too, without masking them with old data.
        finished_ms = state.now.().monotonic_ms

        updated = %{
          state
          | last_error: error,
            refresh_after_ms: finished_ms,
            retry_after_ms: finished_ms + state.retry_cooldown_ms
        }

        {:reply, {:error, error}, updated}
    end
  end

  defp fallback(%{value: nil}, error), do: {:error, error}
  defp fallback(state, %Error{kind: :temporary}), do: {:ok, %{state.value | stale: true}}
  defp fallback(_state, error), do: {:error, error}

  defp current_time do
    %{
      monotonic_ms: System.monotonic_time(:millisecond),
      utc: DateTime.utc_now()
    }
  end
end
