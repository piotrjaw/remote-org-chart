defmodule RemoteOrgChart.Remote.FixtureClientTest do
  use ExUnit.Case, async: true

  alias RemoteOrgChart.Fixture
  alias RemoteOrgChart.Remote.FixtureClient

  test "reads all cursor pages without using the network" do
    assert {:ok, result} =
             FixtureClient.fetch(fixture_directory: Fixture.directory())

    assert result.identity == Fixture.read_json!("identity_current.json")
    assert result.page_count == 3
    assert length(result.employments) == 30
    assert hd(result.employments)["full_name"] == "Ada North"
    assert List.last(result.employments)["full_name"] == "Rowan Lee"
  end

  @tag :tmp_dir
  test "rejects a fixture whose declared cursor chain changed", %{tmp_dir: tmp_dir} do
    for filename <- [
          "identity_current.json",
          "employments_bulk_complex_page_1.json",
          "employments_bulk_complex_page_2.json",
          "employments_bulk_complex_page_3.json"
        ] do
      File.cp!(
        Path.join(Fixture.directory(), filename),
        Path.join(tmp_dir, filename)
      )
    end

    page_two_path = Path.join(tmp_dir, "employments_bulk_complex_page_2.json")

    changed_page =
      page_two_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("next_cursor", "unexpected-cursor")

    File.write!(page_two_path, Jason.encode!(changed_page))

    assert {:error, error} = FixtureClient.fetch(fixture_directory: tmp_dir)
    assert error.kind == :invalid_response
    assert error.operation == :fixture
  end
end
