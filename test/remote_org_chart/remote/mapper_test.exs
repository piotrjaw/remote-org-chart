defmodule RemoteOrgChart.Remote.MapperTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.Fixture
  alias RemoteOrgChart.Remote.Mapper

  test "projects documented company and employment fields into the internal model" do
    identity = Fixture.read_json!("identity_current.json")
    employments = Fixture.complex_employment_pages!() |> List.flatten()

    assert {:ok, snapshot} = Mapper.map(identity, employments)
    assert snapshot.company.id == "00000000-0000-4000-8000-000000000001"
    assert snapshot.company.name == "Acme Sandbox Corp"
    assert length(snapshot.people) == 30

    assert person =
             Enum.find(
               snapshot.people,
               &(&1.id == "10000000-0000-4000-8000-000000000002")
             )

    assert person.name == "Marta Zielińska"
    assert person.title == "Chief Technology Officer"

    assert person.department == %{
             id: "20000000-0000-4000-8000-000000000101",
             name: "Engineering"
           }

    assert person.manager == %{
             id: "10000000-0000-4000-8000-000000000001",
             name: "Ada North"
           }

    assert person.status == "active"
    assert person.employment_type == "employee"
    assert person.employment_model == "eor"
    refute Map.has_key?(Map.from_struct(person), :work_email)
    refute Map.has_key?(Map.from_struct(person), :manager_email)
  end

  test "skips missing IDs and replaces blank names without retaining sensitive fields" do
    identity = Fixture.read_json!("identity_current.json")
    pathological = Fixture.read_json!("employments_bulk_pathological.json")

    assert {:ok, snapshot} = Mapper.map(identity, pathological["data"])
    assert length(snapshot.people) == 7
    refute Enum.any?(snapshot.people, &is_nil(&1.id))

    assert Enum.any?(
             snapshot.people,
             &(&1.id == "90000000-0000-4000-8000-000000000006" and
                 &1.name == "Unknown employee")
           )

    assert %{code: "missing_id", index: 6} in snapshot.warnings

    assert %{
             code: "missing_name",
             employment_id: "90000000-0000-4000-8000-000000000006"
           } in snapshot.warnings

    Enum.each(snapshot.people, fn person ->
      projected = Map.from_struct(person)
      refute Map.has_key?(projected, :work_email)
      refute Map.has_key?(projected, :manager_email)
      refute Map.has_key?(projected, :files)
    end)

    Enum.each(snapshot.warnings, fn warning ->
      refute Map.has_key?(warning, :email)
    end)
  end

  test "returns a typed invalid-response error for a malformed company" do
    invalid_identities = [
      %{},
      %{"data" => %{}},
      %{"data" => %{"company" => %{"id" => "", "name" => "Acme"}}},
      %{"data" => %{"company" => %{"id" => "company-id", "name" => "   "}}},
      %{"data" => %{"company" => %{"id" => 123, "name" => "Acme"}}}
    ]

    Enum.each(invalid_identities, fn identity ->
      assert {:error, error} = Mapper.map(identity, [])
      assert error.kind == :invalid_response
    end)
  end

  test "returns a typed invalid-response error for malformed employment collections" do
    identity = Fixture.read_json!("identity_current.json")

    invalid_collections = [
      nil,
      "not-a-list",
      [%{"id" => "valid", "full_name" => "Valid"}, "not-an-employment-map"]
    ]

    Enum.each(invalid_collections, fn employments ->
      assert {:error, error} = Mapper.map(identity, employments)
      assert error.kind == :invalid_response
    end)
  end
end
