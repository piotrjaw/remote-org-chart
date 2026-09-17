defmodule RemoteOrgChart.HierarchyTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.Fixture
  alias RemoteOrgChart.Hierarchy
  alias RemoteOrgChart.Remote.Mapper

  test "reports of archived managers become roots while keeping their own reports" do
    identity = Fixture.read_json!("identity_current.json")

    people = [
      %{"id" => "archived", "full_name" => "Archived Manager", "status" => " ARCHIVED "},
      %{"id" => "active", "full_name" => "Active Manager", "manager_employment_id" => "archived"},
      %{"id" => "child", "full_name" => "Active Report", "manager_employment_id" => "active"}
    ]

    assert {:ok, snapshot} = Mapper.map(identity, people)
    chart = Hierarchy.build(snapshot)
    assert chart.root_count == 2
    assert chart.employee_count == 3
    active = Enum.find(chart.roots, &(&1.id == "active"))
    assert active.manager_archived
    assert active.manager.id == "archived"
    assert Enum.map(active.reports, & &1.id) == ["child"]
    refute hd(active.reports).manager_archived
    assert Enum.find(chart.roots, &(&1.id == "archived")).reports == []

    result = %RemoteOrgChart.RemoteCache.Result{
      chart: chart,
      fetched_at: DateTime.utc_now(),
      stale: false
    }

    serialized = RemoteOrgChartWeb.OrgChartSerializer.to_map(result)
    assert Enum.find(serialized.roots, &(&1.id == "active")).manager_archived
  end

  test "builds every complex fixture person after resolving managers across pages" do
    identity = Fixture.read_json!("identity_current.json")
    employments = Fixture.complex_employment_pages!() |> List.flatten()
    assert {:ok, snapshot} = Mapper.map(identity, employments)

    chart = Hierarchy.build(snapshot)
    all_nodes = flatten(chart.roots)

    assert chart.employee_count == 30
    assert length(all_nodes) == 30
    assert MapSet.size(MapSet.new(all_nodes, & &1.id)) == 30
    assert chart.root_count == 4
    assert maximum_depth(chart.roots) == 5

    assert Enum.map(chart.roots, & &1.name) == [
             "Ada North",
             "Aisha Bello",
             "Kenji Sato",
             "Rowan Lee"
           ]

    ada = find_node(chart.roots, "10000000-0000-4000-8000-000000000001")

    assert Enum.map(ada.reports, & &1.name) == [
             "Diego Costa",
             "Hugo Laurent",
             "Lars Sørensen",
             "Marta Zielińska",
             "Priya Nair",
             "Samira Khan"
           ]

    anika = find_node(chart.roots, "10000000-0000-4000-8000-000000000021")

    assert Enum.any?(
             anika.reports,
             &(&1.id == "10000000-0000-4000-8000-000000000011")
           )
  end

  test "deduplicates and repairs self-references and cycles deterministically" do
    identity = Fixture.read_json!("identity_current.json")
    pathological = Fixture.read_json!("employments_bulk_pathological.json")
    assert {:ok, snapshot} = Mapper.map(identity, pathological["data"])

    chart = Hierarchy.build(snapshot)
    all_nodes = flatten(chart.roots)

    assert chart.employee_count == 6
    assert length(all_nodes) == 6
    assert MapSet.size(MapSet.new(all_nodes, & &1.id)) == 6

    assert find_node(chart.roots, "90000000-0000-4000-8000-000000000005").name ==
             "Duplicate Primary"

    assert Enum.any?(
             chart.roots,
             &(&1.id == "90000000-0000-4000-8000-000000000001")
           )

    assert cycle_root =
             Enum.find(
               chart.roots,
               &(&1.id == "90000000-0000-4000-8000-000000000002")
             )

    assert length(flatten([cycle_root])) == 3

    assert %{
             code: "cycle_detected",
             employment_ids: [
               "90000000-0000-4000-8000-000000000002",
               "90000000-0000-4000-8000-000000000003",
               "90000000-0000-4000-8000-000000000004"
             ],
             broken_at: "90000000-0000-4000-8000-000000000002"
           } in chart.warnings

    warning_codes = MapSet.new(chart.warnings, & &1.code)

    assert MapSet.subset?(
             MapSet.new([
               "missing_id",
               "missing_name",
               "duplicate_id",
               "self_manager",
               "cycle_detected"
             ]),
             warning_codes
           )

    assert Hierarchy.build(snapshot) == chart
  end

  test "keeps reports with missing or external managers as warned roots" do
    identity = Fixture.read_json!("identity_current.json")
    employments = Fixture.complex_employment_pages!() |> List.flatten()
    assert {:ok, snapshot} = Mapper.map(identity, employments)

    chart = Hierarchy.build(snapshot)
    root_ids = MapSet.new(chart.roots, & &1.id)

    assert "10000000-0000-4000-8000-000000000028" in root_ids
    assert "10000000-0000-4000-8000-000000000029" in root_ids

    assert %{
             code: "unresolved_manager",
             employment_id: "10000000-0000-4000-8000-000000000028",
             manager_employment_id: "10000000-0000-4000-8000-000000000999"
           } in chart.warnings

    assert %{
             code: "external_manager",
             employment_id: "10000000-0000-4000-8000-000000000029",
             manager_name: "Morgan External"
           } in chart.warnings

    Enum.each(chart.warnings, fn warning ->
      refute Map.has_key?(warning, :email)
      refute Map.has_key?(warning, :manager_email)
    end)
  end

  defp flatten(nodes) do
    Enum.flat_map(nodes, fn node -> [node | flatten(node.reports)] end)
  end

  defp find_node(nodes, id) do
    Enum.find_value(nodes, fn node ->
      if node.id == id, do: node, else: find_node(node.reports, id)
    end)
  end

  defp maximum_depth([]), do: 0

  defp maximum_depth(nodes) do
    nodes
    |> Enum.map(&(1 + maximum_depth(&1.reports)))
    |> Enum.max()
  end
end
