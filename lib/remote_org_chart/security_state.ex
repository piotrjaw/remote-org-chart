defmodule RemoteOrgChart.SecurityState do
  @moduledoc "Single-instance, bounded security state. Restarting revokes all sessions."
  use GenServer

  def start_link(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  def create_session(version, server \\ __MODULE__),
    do: GenServer.call(server, {:create, version})

  def valid_session?(token, version, server \\ __MODULE__) do
    is_binary(token) and GenServer.call(server, {:valid, hash(token), version})
  end

  def revoke_session(token, server \\ __MODULE__),
    do: GenServer.call(server, {:revoke, hash(token)})

  def allow_login(server \\ __MODULE__), do: GenServer.call(server, :login)

  def remember_webhook(signature, server \\ __MODULE__),
    do: GenServer.call(server, {:webhook, hash(signature)})

  @impl true
  def init(options) do
    Process.send_after(self(), :prune, 60_000)

    {:ok,
     %{
       sessions: %{},
       webhooks: %{},
       login: nil,
       now: Keyword.get(options, :now, fn -> System.monotonic_time(:millisecond) end),
       session_ttl_ms: Keyword.get(options, :session_ttl_ms, 8 * 60 * 60 * 1000),
       login_limit: Keyword.get(options, :login_limit, 10),
       capacity: Keyword.get(options, :capacity, 10_000)
     }}
  end

  @impl true
  def handle_call({:create, version}, _from, state) do
    state = prune(state)

    if map_size(state.sessions) < state.capacity do
      token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      entry = {state.now.() + state.session_ttl_ms, version}
      {:reply, {:ok, token}, %{state | sessions: Map.put(state.sessions, hash(token), entry)}}
    else
      {:reply, {:error, :capacity}, state}
    end
  end

  def handle_call({:valid, key, version}, _from, state) do
    valid =
      case state.sessions[key] do
        {expires, ^version} -> expires > state.now.()
        _ -> false
      end

    {:reply, valid, state}
  end

  def handle_call({:revoke, key}, _from, state) do
    {:reply, :ok, %{state | sessions: Map.delete(state.sessions, key)}}
  end

  def handle_call(:login, _from, state) do
    now = state.now.()

    {count, expires} =
      case state.login do
        {count, expires} when expires > now -> {count, expires}
        _ -> {0, now + 60_000}
      end

    if count < state.login_limit do
      {:reply, :ok, %{state | login: {count + 1, expires}}}
    else
      {:reply, {:error, max(1, ceil((expires - now) / 1000))}, state}
    end
  end

  def handle_call({:webhook, key}, _from, state) do
    state = prune(state)

    cond do
      Map.has_key?(state.webhooks, key) ->
        {:reply, :duplicate, state}

      map_size(state.webhooks) >= state.capacity ->
        {:reply, :full, state}

      true ->
        {:reply, :new,
         %{state | webhooks: Map.put(state.webhooks, key, {state.now.() + 600_000, nil})}}
    end
  end

  @impl true
  def handle_info(:prune, state) do
    Process.send_after(self(), :prune, 60_000)
    {:noreply, prune(state)}
  end

  defp prune(state) do
    now = state.now.()
    keep = fn {_key, {expires, _}} -> expires > now end

    %{
      state
      | sessions: Map.filter(state.sessions, keep),
        webhooks: Map.filter(state.webhooks, keep)
    }
  end

  defp hash(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(value))
end
