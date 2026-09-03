defmodule RemoteOrgChart.Fixture do
  @moduledoc false

  @fixture_directory Path.expand("../../fixtures/remote", __DIR__)

  def read_json!(filename) do
    @fixture_directory
    |> Path.join(filename)
    |> File.read!()
    |> Jason.decode!()
  end

  def complex_employment_pages! do
    1..3
    |> Enum.map(fn page ->
      "employments_bulk_complex_page_#{page}.json"
      |> read_json!()
      |> Map.fetch!("data")
    end)
  end
end
