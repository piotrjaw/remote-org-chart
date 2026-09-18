defmodule RemoteOrgChart.RemoteTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  require Logger

  alias RemoteOrgChart.Fixture
  alias RemoteOrgChart.Remote
  alias RemoteOrgChart.Remote.Error

  defmodule SourceStub do
    @behaviour RemoteOrgChart.Remote.Source

    @impl true
    def fetch(options), do: Keyword.fetch!(options, :result)
  end

  defmodule FailingSource do
    @behaviour RemoteOrgChart.Remote.Source

    @impl true
    def fetch(_options), do: raise("private upstream body and token")
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
    Logger.metadata(private_body: "private upstream body and token")

    log =
      capture_log(Application.fetch_env!(:logger, :console), fn ->
        assert {:error, ^error} =
                 Remote.fetch_chart(
                   source: SourceStub,
                   source_options: [result: {:error, error}]
                 )
      end)

    assert log =~ "remote_error_kind=authentication"
    assert log =~ "remote_operation=identity"
    assert log =~ "remote_duration_ms="
    refute log =~ "Ada North"
    refute log =~ "@acme"
    refute log =~ "upstream body"
  end

  test "logs unexpected exception type without its private message" do
    log =
      capture_log(Application.fetch_env!(:logger, :console), fn ->
        assert {:error, %Error{kind: :internal}} = Remote.fetch_chart(source: FailingSource)
      end)

    assert log =~ "remote_exception=RuntimeError"
    refute log =~ "private upstream body and token"
  end
end
