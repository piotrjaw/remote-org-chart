defmodule RemoteOrgChart.Remote.FixtureClient do
  @moduledoc """
  Reads committed Remote-shaped pages for explicit local fixture mode.
  """

  @behaviour RemoteOrgChart.Remote.Source

  alias RemoteOrgChart.Remote.Error

  @pages [
    {"employments_bulk_complex_page_1.json", "fixture-cursor-page-2"},
    {"employments_bulk_complex_page_2.json", "fixture-cursor-page-3"},
    {"employments_bulk_complex_page_3.json", nil}
  ]

  @impl true
  def fetch(options \\ []) do
    fixture_directory =
      Keyword.get(
        options,
        :fixture_directory,
        Application.get_env(:remote_org_chart, :remote_fixture_directory)
      )

    with directory when is_binary(directory) <- fixture_directory,
         {:ok, identity} <- read_json(directory, "identity_current.json"),
         {:ok, employments} <- read_pages(directory) do
      {:ok,
       %{
         identity: identity,
         employments: employments,
         page_count: length(@pages)
       }}
    else
      _invalid -> {:error, Error.invalid_response(:fixture)}
    end
  end

  defp read_pages(directory) do
    Enum.reduce_while(@pages, {:ok, []}, fn {filename, expected_cursor}, {:ok, employments} ->
      with {:ok, page} <- read_json(directory, filename),
           %{"data" => data, "next_cursor" => ^expected_cursor} when is_list(data) <- page,
           true <- Enum.all?(data, &is_map/1) do
        {:cont, {:ok, employments ++ data}}
      else
        _invalid -> {:halt, {:error, Error.invalid_response(:fixture)}}
      end
    end)
  end

  defp read_json(directory, filename) do
    with {:ok, contents} <- File.read(Path.join(directory, filename)),
         {:ok, decoded} when is_map(decoded) <- Jason.decode(contents) do
      {:ok, decoded}
    else
      _invalid -> {:error, Error.invalid_response(:fixture)}
    end
  end
end
