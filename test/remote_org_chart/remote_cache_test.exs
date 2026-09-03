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
