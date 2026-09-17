defmodule RemoteOrgChart.RemoteCacheTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.Hierarchy.{Chart, Node}
  alias RemoteOrgChart.Remote.{Company, Error}
  alias RemoteOrgChart.RemoteCache

  test "fetches once and reuses a fresh normalized chart" do
    chart = chart("version-1")

    counter =
      start_supervised!({Agent, fn -> 0 end},
        id: {Agent, make_ref()}
      )

    clock =
      start_supervised!({Agent, fn -> now(0) end},
        id: {Agent, make_ref()}
      )

    fetcher = fn ->
      Agent.get_and_update(counter, fn count ->
        {{:ok, chart}, count + 1}
      end)
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil, fetcher: fetcher, now: fn -> Agent.get(clock, & &1) end, ttl_ms: 5_000}
      )

    assert {:ok, first} = RemoteCache.get(cache)
    assert {:ok, second} = RemoteCache.get(cache)
    assert first.chart == chart
    assert second.chart == chart
    assert DateTime.compare(first.fetched_at, ~U[2026-09-03 12:00:00Z]) == :eq
    refute first.stale
    refute second.stale
    assert Agent.get(counter, & &1) == 1
  end

  test "refetches after expiry and on a forced refresh" do
    responses =
      start_agent(fn ->
        [chart("version-1"), chart("version-2"), chart("version-3")]
      end)

    clock = start_agent(fn -> now(0) end)

    fetcher = fn ->
      Agent.get_and_update(responses, fn [next | remaining] ->
        {{:ok, next}, remaining}
      end)
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil, fetcher: fetcher, now: fn -> Agent.get(clock, & &1) end, ttl_ms: 5_000}
      )

    assert {:ok, first} = RemoteCache.get(cache)
    assert hd(first.chart.roots).id == "root-version-1"

    Agent.update(clock, fn _current -> now(5_001) end)
    assert {:ok, expired} = RemoteCache.get(cache)
    assert hd(expired.chart.roots).id == "root-version-2"

    assert {:ok, refreshed} = RemoteCache.refresh(cache)
    assert hd(refreshed.chart.roots).id == "root-version-3"
  end

  test "coalesces invalidation before refetching on the next read" do
    responses = start_agent(fn -> [chart("version-1"), chart("version-2")] end)
    clock = start_agent(fn -> now(0) end)

    fetcher = fn ->
      Agent.get_and_update(responses, fn [next | remaining] ->
        {{:ok, next}, remaining}
      end)
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         fetcher: fetcher,
         now: fn -> Agent.get(clock, & &1) end,
         ttl_ms: 5_000,
         invalidation_debounce_ms: 2_000}
      )

    assert {:ok, initial} = RemoteCache.get(cache)
    assert hd(initial.chart.roots).id == "root-version-1"

    assert :ok = RemoteCache.invalidate(cache)
    :sys.get_state(cache)
    Agent.update(clock, fn _current -> now(1_000) end)
    assert :ok = RemoteCache.invalidate(cache)
    :sys.get_state(cache)

    Agent.update(clock, fn _current -> now(2_999) end)
    assert {:ok, debounced} = RemoteCache.get(cache)
    assert hd(debounced.chart.roots).id == "root-version-1"

    Agent.update(clock, fn _current -> now(3_000) end)
    assert {:ok, refreshed} = RemoteCache.get(cache)
    assert hd(refreshed.chart.roots).id == "root-version-2"
  end

  test "TTL expiry still refreshes during an invalidation burst" do
    responses = start_agent(fn -> [chart("version-1"), chart("version-2")] end)
    clock = start_agent(fn -> now(0) end)

    fetcher = fn ->
      Agent.get_and_update(responses, fn [next | remaining] ->
        {{:ok, next}, remaining}
      end)
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         fetcher: fetcher,
         now: fn -> Agent.get(clock, & &1) end,
         ttl_ms: 1_000,
         invalidation_debounce_ms: 2_000}
      )

    assert {:ok, initial} = RemoteCache.get(cache)
    assert hd(initial.chart.roots).id == "root-version-1"

    Agent.update(clock, fn _current -> now(900) end)
    assert :ok = RemoteCache.invalidate(cache)
    Agent.update(clock, fn _current -> now(1_000) end)

    assert {:ok, refreshed} = RemoteCache.get(cache)
    assert hd(refreshed.chart.roots).id == "root-version-2"
  end

  test "invalidation does not wait behind an in-progress refresh" do
    test_process = self()
    clock = start_agent(fn -> now(0) end)
    fetch_count = start_agent(fn -> 0 end)

    fetcher = fn ->
      case Agent.get_and_update(fetch_count, fn count -> {count, count + 1} end) do
        0 ->
          {:ok, chart("version-1")}

        1 ->
          send(test_process, {:refresh_started, self()})
          receive do: (:continue_refresh -> {:ok, chart("version-2")})
      end
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil, fetcher: fetcher, now: fn -> Agent.get(clock, & &1) end, ttl_ms: 1_000}
      )

    assert {:ok, _initial} = RemoteCache.get(cache)
    Agent.update(clock, fn _current -> now(1_000) end)

    refresh = Task.async(fn -> RemoteCache.get(cache) end)
    assert_receive {:refresh_started, worker}

    invalidation = Task.async(fn -> RemoteCache.invalidate(cache) end)
    assert {:ok, :ok} = Task.yield(invalidation, 100)

    send(worker, :continue_refresh)
    assert {:ok, {:ok, _refreshed}} = Task.yield(refresh, 1_000)
  end

  test "returns an existing snapshot as stale for a temporary fetch failure" do
    responses =
      start_agent(fn ->
        [
          {:ok, chart("version-1")},
          {:error, Error.temporary(:http, 30)}
        ]
      end)

    clock = start_agent(fn -> now(0) end)

    fetcher = fn ->
      Agent.get_and_update(responses, fn [next | remaining] ->
        {next, remaining}
      end)
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil, fetcher: fetcher, now: fn -> Agent.get(clock, & &1) end, ttl_ms: 5_000}
      )

    assert {:ok, fresh} = RemoteCache.get(cache)
    Agent.update(clock, fn _current -> now(5_001) end)
    assert {:ok, stale} = RemoteCache.get(cache)

    assert stale.chart == fresh.chart
    assert stale.fetched_at == fresh.fetched_at
    assert stale.stale
  end

  test "backs off invalidated refreshes after a temporary failure" do
    responses =
      start_agent(fn ->
        [
          {:ok, chart("version-1")},
          {:error, Error.temporary(:http)},
          {:ok, chart("version-2")}
        ]
      end)

    clock = start_agent(fn -> now(0) end)

    fetcher = fn ->
      Agent.get_and_update(responses, fn [next | remaining] ->
        {next, remaining}
      end)
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         fetcher: fetcher,
         now: fn -> Agent.get(clock, & &1) end,
         ttl_ms: 300_000,
         invalidation_debounce_ms: 0,
         retry_cooldown_ms: 30_000}
      )

    assert {:ok, initial} = RemoteCache.get(cache)
    refute initial.stale
    assert :ok = RemoteCache.invalidate(cache)

    assert {:ok, failed_refresh} = RemoteCache.get(cache)
    assert failed_refresh.stale
    assert {:ok, backed_off} = RemoteCache.get(cache)
    assert backed_off.stale
    assert hd(backed_off.chart.roots).id == "root-version-1"

    Agent.update(clock, fn _current -> now(30_000) end)
    assert {:ok, recovered} = RemoteCache.get(cache)
    refute recovered.stale
    assert hd(recovered.chart.roots).id == "root-version-2"
  end

  test "never falls back to stale data for authentication, invalid, or internal failures" do
    errors = [
      Error.authentication(:http),
      Error.invalid_response(:http),
      %Error{kind: :internal, operation: :source}
    ]

    Enum.each(errors, fn expected_error ->
      responses =
        start_agent(fn ->
          [
            {:ok, chart("version-1")},
            {:error, expected_error}
          ]
        end)

      fetcher = fn ->
        Agent.get_and_update(responses, fn [next | remaining] ->
          {next, remaining}
        end)
      end

      cache =
        start_supervised!(
          {RemoteCache, name: nil, fetcher: fetcher, now: fn -> now(0) end, ttl_ms: 5_000},
          id: {RemoteCache, make_ref()}
        )

      assert {:ok, fresh} = RemoteCache.get(cache)
      assert {:error, ^expected_error} = RemoteCache.refresh(cache)
      assert {:ok, still_fresh} = RemoteCache.get(cache)
      assert still_fresh.chart == fresh.chart
      refute still_fresh.stale
    end)
  end

  test "returns a temporary error when no stale snapshot exists" do
    error = Error.temporary(:http)

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil, fetcher: fn -> {:error, error} end, now: fn -> now(0) end, ttl_ms: 5_000}
      )

    assert {:error, ^error} = RemoteCache.get(cache)
  end

  test "serializes concurrent cache misses into one fetch" do
    test_process = self()
    chart = chart("single-flight")

    fetcher = fn ->
      send(test_process, {:fetch_started, self()})

      receive do
        :release_fetch -> {:ok, chart}
      end
    end

    cache =
      start_supervised!(
        {RemoteCache, name: nil, fetcher: fetcher, now: fn -> now(0) end, ttl_ms: 5_000}
      )

    tasks =
      for _call <- 1..5 do
        Task.async(fn -> RemoteCache.get(cache) end)
      end

    assert_receive {:fetch_started, cache_process}
    refute_receive {:fetch_started, _other_process}, 25
    send(cache_process, :release_fetch)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.uniq(results) |> length() == 1
    refute_receive {:fetch_started, _other_process}, 25
  end

  test "runs as a named child of the application supervisor" do
    assert is_pid(Process.whereis(RemoteCache))
  end

  test "a fetch lasting longer than five seconds returns its result" do
    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         ttl_ms: 300_000,
         fetcher: fn ->
           Process.sleep(5_100)
           {:ok, chart("slow")}
         end}
      )

    assert {:ok, result} = RemoteCache.get(cache)
    assert hd(result.chart.roots).id == "root-slow"
  end

  test "the overall fetch deadline returns a temporary error and terminates the worker" do
    parent = self()

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         ttl_ms: 300_000,
         fetch_timeout_ms: 50,
         fetcher: fn ->
           send(parent, {:worker, self()})
           Process.sleep(:infinity)
         end}
      )

    assert {:error, %Error{kind: :temporary}} = RemoteCache.get(cache)
    assert_receive {:worker, worker}
    refute Process.alive?(worker)
    assert Process.alive?(cache)
  end

  test "Retry-After is measured from failure completion, including with an empty cache" do
    clock = start_agent(fn -> now(0) end)
    calls = start_agent(fn -> 0 end)

    fetcher = fn ->
      case Agent.get_and_update(calls, fn n -> {n, n + 1} end) do
        0 ->
          Agent.update(clock, fn _ -> now(10_000) end)
          {:error, Error.temporary(:http, 120)}

        _ ->
          {:ok, chart("recovered")}
      end
    end

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil, ttl_ms: 300_000, now: fn -> Agent.get(clock, & &1) end, fetcher: fetcher}
      )

    assert {:error, %Error{kind: :temporary}} = RemoteCache.get(cache)
    Agent.update(clock, fn _ -> now(129_999) end)
    assert {:error, %Error{kind: :temporary}} = RemoteCache.get(cache)
    Agent.update(clock, fn _ -> now(130_000) end)
    assert {:ok, result} = RemoteCache.get(cache)
    assert hd(result.chart.roots).id == "root-recovered"
  end

  test "a timed-out refresh preserves the last complete chart as stale" do
    calls = start_agent(fn -> 0 end)

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         ttl_ms: 300_000,
         fetch_timeout_ms: 50,
         fetcher: fn ->
           case Agent.get_and_update(calls, fn n -> {n, n + 1} end) do
             0 -> {:ok, chart("saved")}
             _ -> Process.sleep(:infinity)
           end
         end}
      )

    assert {:ok, original} = RemoteCache.get(cache)
    assert {:ok, stale} = RemoteCache.refresh(cache)
    assert stale.stale
    assert stale.chart == original.chart
    assert {:ok, ^stale} = RemoteCache.get(cache)
  end

  test "concurrent forced refreshes share one result and honor a completion cooldown" do
    parent = self()
    clock = start_agent(fn -> now(0) end)

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         ttl_ms: 300_000,
         now: fn -> Agent.get(clock, & &1) end,
         fetcher: fn ->
           send(parent, {:manual_fetch, self()})
           receive do: (:finish -> {:ok, chart("manual")})
         end}
      )

    tasks = for _ <- 1..5, do: Task.async(fn -> RemoteCache.refresh(cache) end)
    assert_receive {:manual_fetch, worker}
    Agent.update(clock, fn _ -> now(10_000) end)
    send(worker, :finish)
    results = Enum.map(tasks, &Task.await/1)
    assert length(Enum.uniq(results)) == 1
    refute_receive {:manual_fetch, _}, 20
    Agent.update(clock, fn _ -> now(39_999) end)
    assert {:ok, _} = RemoteCache.refresh(cache)
    refute_receive {:manual_fetch, _}, 20
    Agent.update(clock, fn _ -> now(40_000) end)
    task = Task.async(fn -> RemoteCache.refresh(cache) end)
    assert_receive {:manual_fetch, next}
    send(next, :finish)
    assert {:ok, _} = Task.await(task)
  end

  test "manual refresh cannot bypass upstream Retry-After even without a snapshot" do
    parent = self()

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         ttl_ms: 300_000,
         fetcher: fn ->
           send(parent, :fetch_attempt)
           {:error, Error.temporary(:http, 120)}
         end}
      )

    assert {:error, _} = RemoteCache.get(cache)
    assert_receive :fetch_attempt
    assert {:error, _} = RemoteCache.refresh(cache)
    refute_receive :fetch_attempt, 20
  end

  test "manual cooldown returns a newer webhook snapshot rather than the old manual result" do
    responses = start_agent(fn -> [chart("old"), chart("new")] end)
    clock = start_agent(fn -> now(0) end)

    cache =
      start_supervised!(
        {RemoteCache,
         name: nil,
         ttl_ms: 300_000,
         now: fn -> Agent.get(clock, & &1) end,
         fetcher: fn ->
           Agent.get_and_update(responses, fn [head | tail] -> {{:ok, head}, tail} end)
         end}
      )

    assert {:ok, _} = RemoteCache.refresh(cache)
    RemoteCache.invalidate(cache)
    :sys.get_state(cache)
    Agent.update(clock, fn _ -> now(2000) end)
    assert {:ok, latest} = RemoteCache.get(cache)
    assert hd(latest.chart.roots).id == "root-new"
    assert {:ok, ^latest} = RemoteCache.refresh(cache)
  end

  defp chart(version) do
    root = %Node{
      id: "root-#{version}",
      name: "Root #{version}",
      title: nil,
      department: nil,
      manager: nil,
      status: "active",
      employment_type: "employee",
      employment_model: "eor",
      reports: []
    }

    %Chart{
      company: %Company{id: "company", name: "Acme"},
      roots: [root],
      warnings: [],
      employee_count: 1,
      root_count: 1
    }
  end

  defp now(monotonic_ms) do
    %{
      monotonic_ms: monotonic_ms,
      utc: DateTime.add(~U[2026-09-03 12:00:00Z], monotonic_ms, :millisecond)
    }
  end

  defp start_agent(initializer) do
    start_supervised!({Agent, initializer},
      id: {Agent, make_ref()}
    )
  end
end
