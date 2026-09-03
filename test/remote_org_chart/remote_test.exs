defmodule RemoteOrgChart.RemoteTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias RemoteOrgChart.Fixture
  alias RemoteOrgChart.Remote
  alias RemoteOrgChart.Remote.Error

  defmodule SourceStub do
    @behaviour RemoteOrgChart.Remote.Source

    @impl true
    def fetch(options), do: Keyword.fetch!(options, :result)
  end

  test "maps and builds the configured provider result" do
    raw = %{
      identity: Fixture.read_json!("identity_current.json"),
      employments: Fixture.complex_employment_pages!() |> List.flatten(),
      page_count: 3
    }

    assert {:ok, chart} =
             Remote.fetch_chart(
               source: SourceStub,
               source_options: [result: {:ok, raw}]
             )

    assert chart.company.name == "Acme Sandbox Corp"
    assert chart.employee_count == 30
    assert chart.root_count == 4
  end

  test "preserves typed provider failures without logging private fixture data" do
    error = Error.authentication(:identity)

    log =
      capture_log(fn ->
        assert {:error, ^error} =
                 Remote.fetch_chart(
                   source: SourceStub,
                   source_options: [result: {:error, error}]
                 )
      end)

    refute log =~ "Ada North"
    refute log =~ "@acme"
    refute log =~ "upstream body"
  end
end
