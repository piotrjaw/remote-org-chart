defmodule RemoteOrgChart.SecurityStateTest do
  use ExUnit.Case, async: true
  alias RemoteOrgChart.SecurityState

  setup do
    clock = start_supervised!({Agent, fn -> 0 end})

    store =
      start_supervised!(
        {SecurityState,
         name: nil, now: fn -> Agent.get(clock, & &1) end, session_ttl_ms: 1000, login_limit: 2}
      )

    %{store: store, clock: clock}
  end

  test "sessions expire, revoke, and bind to the credential version", %{
    store: store,
    clock: clock
  } do
    {:ok, token} = SecurityState.create_session("v1", store)
    assert SecurityState.valid_session?(token, "v1", store)
    refute SecurityState.valid_session?(token, "v2", store)
    refute SecurityState.valid_session?(nil, "v1", store)
    :ok = SecurityState.revoke_session(token, store)
    refute SecurityState.valid_session?(token, "v1", store)
    {:ok, token} = SecurityState.create_session("v1", store)
    Agent.update(clock, fn _ -> 1000 end)
    refute SecurityState.valid_session?(token, "v1", store)
  end

  test "login budget is atomic and recovers after its window", %{store: store, clock: clock} do
    results =
      1..8
      |> Task.async_stream(fn _ -> SecurityState.allow_login(store) end)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &(&1 == :ok)) == 2
    assert Enum.count(results, &(&1 == {:error, 60})) == 6
    Agent.update(clock, fn _ -> 60_000 end)
    assert :ok = SecurityState.allow_login(store)
  end

  test "security state is bounded and rejects new entries when full" do
    store = start_supervised!({SecurityState, name: nil, capacity: 1}, id: :bounded_store)
    {:ok, token} = SecurityState.create_session("v1", store)
    assert {:error, :capacity} = SecurityState.create_session("v1", store)
    assert SecurityState.valid_session?(token, "v1", store)
    assert :new = SecurityState.remember_webhook("first", store)
    assert :full = SecurityState.remember_webhook("second", store)
    assert :duplicate = SecurityState.remember_webhook("first", store)
  end

  test "webhook deliveries are remembered atomically", %{store: store, clock: clock} do
    assert :new = SecurityState.remember_webhook("signature", store)
    assert :duplicate = SecurityState.remember_webhook("signature", store)
    Agent.update(clock, fn _ -> 600_001 end)
    assert :new = SecurityState.remember_webhook("signature", store)
  end
end
