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

  test "only an archived manager's direct reports detach, preserving both remaining teams" do
    chart =
      build_people([
        employment("leader", nil),
        employment("archived", "leader", "archived"),
        employment("sibling", "leader"),
        employment("team-lead", "archived"),
        employment("other-report", "archived"),
        employment("team-member", "team-lead")
      ])

    assert Enum.map(chart.roots, & &1.id) == ["leader", "other-report", "team-lead"]
    assert Enum.map(find_node(chart.roots, "leader").reports, & &1.id) == ["archived", "sibling"]
    assert Enum.map(find_node(chart.roots, "team-lead").reports, & &1.id) == ["team-member"]
    assert find_node(chart.roots, "archived").reports == []
    assert find_node(chart.roots, "other-report").manager_archived
    assert find_node(chart.roots, "team-lead").manager_archived
    refute find_node(chart.roots, "team-member").manager_archived
    assert chart.employee_count == 6
    assert chart.root_count == 3
    assert chart.warnings == []
  end

  test "consecutive archived managers each release their direct reports" do
    chart =
      build_people([
        employment("first", nil, "archived"),
        employment("second", "first", "archived"),
        employment("third", "second"),
        employment("fourth", "third")
      ])

    assert Enum.map(chart.roots, & &1.id) == ["first", "second", "third"]
    assert find_node(chart.roots, "first").reports == []
    assert find_node(chart.roots, "second").reports == []
    assert find_node(chart.roots, "second").manager_archived
    assert find_node(chart.roots, "third").manager_archived
    assert Enum.map(find_node(chart.roots, "third").reports, & &1.id) == ["fourth"]
    assert chart.employee_count == 4
  end

  test "archived classification is case insensitive and does not match other statuses" do
    for status <- ["archived", "ARCHIVED", " Archived "] do
      chart = build_people([employment("manager", nil, status), employment("report", "manager")])
      assert chart.root_count == 2
      assert find_node(chart.roots, "report").manager_archived
    end

    for status <- [nil, "", "active", "inactive", "offboarding", "archived_pending"] do
      chart = build_people([employment("manager", nil, status), employment("report", "manager")])
      assert chart.root_count == 1
      assert Enum.map(hd(chart.roots).reports, & &1.id) == ["report"]
      refute find_node(chart.roots, "report").manager_archived
    end
  end

  test "missing and name-only managers are not classified as archived" do
    chart =
      build_people([
        employment("archived", nil, "archived"),
        employment("missing", "absent"),
        Map.put(employment("external", nil), "manager", "archived"),
        employment("unassigned", nil)
      ])

    assert chart.root_count == 4
    assert Enum.all?(chart.roots, &(not &1.manager_archived))

    assert Enum.map(chart.warnings, & &1.code) |> Enum.sort() == [
             "external_manager",
             "unresolved_manager"
           ]
  end

  test "removing an archived-manager edge resolves a cycle without losing employees" do
    chart =
      build_people([
        employment("archived", "active", "archived"),
        employment("active", "archived"),
        employment("report", "active")
      ])

    assert Enum.map(chart.roots, & &1.id) == ["active"]
    assert hd(chart.roots).manager_archived
    assert Enum.map(hd(chart.roots).reports, & &1.id) == ["archived", "report"]
    assert find_node(chart.roots, "archived").reports == []
    assert chart.warnings == []
    assert chart.employee_count == 3
  end

  test "all three-person graphs preserve every employee once and never nest under archived managers" do
    ids = ["a", "b", "c"]
    managers = [nil | ids]

    for ma <- managers,
        mb <- managers,
        mc <- managers,
        sa <- ["active", "archived"],
        sb <- ["active", "archived"],
        sc <- ["active", "archived"] do
      people = [employment("a", ma, sa), employment("b", mb, sb), employment("c", mc, sc)]
      chart = build_people(people)
      nodes = flatten(chart.roots)
      assert Enum.sort(Enum.map(nodes, & &1.id)) == ids
      assert chart.employee_count == 3
      assert chart.root_count == length(chart.roots)
      assert Enum.all?(nodes, fn node -> node.status != "archived" or node.reports == [] end)
      assert build_people(Enum.reverse(people)) == chart
    end
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

  defp employment(id, manager_id, status \\ "active") do
    %{"id" => id, "full_name" => id, "manager_employment_id" => manager_id, "status" => status}
  end

  defp build_people(people) do
    assert {:ok, snapshot} = Mapper.map(Fixture.read_json!("identity_current.json"), people)
    Hierarchy.build(snapshot)
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
