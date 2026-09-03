defmodule RemoteOrgChart.Hierarchy do
  @moduledoc """
  Builds a deterministic organization forest from normalized employments.
  """

  alias RemoteOrgChart.Hierarchy.{Chart, Node}
  alias RemoteOrgChart.Remote.{Person, Snapshot}

  @spec build(Snapshot.t()) :: Chart.t()
  def build(%Snapshot{} = snapshot) do
    {people_by_id, ordered_ids, duplicate_warnings} = deduplicate(snapshot.people)
    {parent_by_child, relationship_warnings} = parent_edges(ordered_ids, people_by_id)
    {parent_by_child, cycle_warnings} = break_cycles(parent_by_child)
    children_by_parent = children_by_parent(parent_by_child)

    roots =
      ordered_ids
      |> Enum.reject(&Map.has_key?(parent_by_child, &1))
      |> Enum.map(&build_node(&1, people_by_id, children_by_parent))
      |> sort_nodes()

    %Chart{
      company: snapshot.company,
      roots: roots,
      warnings:
        snapshot.warnings ++ duplicate_warnings ++ relationship_warnings ++ cycle_warnings,
      employee_count: map_size(people_by_id),
      root_count: length(roots)
    }
  end

  defp deduplicate(people) do
    {people_by_id, ordered_ids, warnings} =
      Enum.reduce(people, {%{}, [], []}, fn person, {by_id, ids, warnings} ->
        if Map.has_key?(by_id, person.id) do
          {by_id, ids, [%{code: "duplicate_id", employment_id: person.id} | warnings]}
        else
          {Map.put(by_id, person.id, person), [person.id | ids], warnings}
        end
      end)

    {people_by_id, Enum.reverse(ordered_ids), Enum.reverse(warnings)}
  end

  defp parent_edges(ordered_ids, people_by_id) do
    ordered_ids
    |> Enum.sort()
    |> Enum.reduce({%{}, []}, fn id, {edges, warnings} ->
      person = Map.fetch!(people_by_id, id)

      case classify_manager(person, people_by_id) do
        {:edge, manager_id} ->
          {Map.put(edges, id, manager_id), warnings}

        {:warning, warning} ->
          {edges, [warning | warnings]}

        :root ->
          {edges, warnings}
      end
    end)
    |> then(fn {edges, warnings} -> {edges, Enum.reverse(warnings)} end)
  end

  defp classify_manager(%Person{manager: nil}, _people_by_id), do: :root

  defp classify_manager(%Person{id: id, manager: %{id: id}}, _people_by_id) do
    {:warning, %{code: "self_manager", employment_id: id}}
  end

  defp classify_manager(
         %Person{id: id, manager: %{id: manager_id}},
         people_by_id
       )
       when is_binary(manager_id) do
    if Map.has_key?(people_by_id, manager_id) do
      {:edge, manager_id}
    else
      {:warning,
       %{
         code: "unresolved_manager",
         employment_id: id,
         manager_employment_id: manager_id
       }}
    end
  end

  defp classify_manager(
         %Person{id: id, manager: %{id: nil, name: manager_name}},
         _people_by_id
       )
       when is_binary(manager_name) do
    {:warning,
     %{
       code: "external_manager",
       employment_id: id,
       manager_name: manager_name
     }}
  end

  defp classify_manager(_person, _people_by_id), do: :root

  defp break_cycles(parent_by_child) do
    cycles =
      parent_by_child
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&cycle_from(&1, parent_by_child))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Enum.sort/1)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(cycles, {parent_by_child, []}, fn cycle_ids, {edges, warnings} ->
      broken_at = Enum.min(cycle_ids)

      warning = %{
        code: "cycle_detected",
        employment_ids: cycle_ids,
        broken_at: broken_at
      }

      {Map.delete(edges, broken_at), warnings ++ [warning]}
    end)
  end

  defp cycle_from(start_id, parent_by_child) do
    walk_parent_edges(start_id, parent_by_child, [], %{})
  end

  defp walk_parent_edges(id, parent_by_child, path, positions) do
    cond do
      Map.has_key?(positions, id) ->
        Enum.drop(path, Map.fetch!(positions, id))

      Map.has_key?(parent_by_child, id) ->
        walk_parent_edges(
          Map.fetch!(parent_by_child, id),
          parent_by_child,
          path ++ [id],
          Map.put(positions, id, length(path))
        )

      true ->
        nil
    end
  end

  defp children_by_parent(parent_by_child) do
    Enum.reduce(parent_by_child, %{}, fn {child_id, parent_id}, children ->
      Map.update(children, parent_id, [child_id], &[child_id | &1])
    end)
  end

  defp build_node(id, people_by_id, children_by_parent) do
    person = Map.fetch!(people_by_id, id)

    reports =
      children_by_parent
      |> Map.get(id, [])
      |> Enum.map(&build_node(&1, people_by_id, children_by_parent))
      |> sort_nodes()

    %Node{
      id: person.id,
      name: person.name,
      title: person.title,
      department: person.department,
      manager: person.manager,
      status: person.status,
      employment_type: person.employment_type,
      employment_model: person.employment_model,
      reports: reports
    }
  end

  defp sort_nodes(nodes) do
    Enum.sort_by(nodes, &{String.downcase(&1.name), &1.id})
  end
end
