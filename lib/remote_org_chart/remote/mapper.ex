defmodule RemoteOrgChart.Remote.Mapper do
  @moduledoc """
  Projects Remote API maps into the deliberately small internal data model.
  """

  alias RemoteOrgChart.Remote.{Company, Error, Person, Snapshot}

  @spec map(term(), term()) :: {:ok, Snapshot.t()} | {:error, Error.t()}
  def map(identity, employments) when is_map(identity) and is_list(employments) do
    with {:ok, company} <- map_company(identity),
         {:ok, {people, warnings}} <- map_people(employments) do
      {:ok,
       %Snapshot{
         company: company,
         people: people,
         warnings: warnings
       }}
    end
  end

  def map(_identity, _employments), do: {:error, Error.invalid_response(:mapping)}

  defp map_company(%{"data" => %{"company" => company}}) when is_map(company) do
    case {optional_string(company["id"]), optional_string(company["name"])} do
      {id, name} when is_binary(id) and is_binary(name) ->
        {:ok, %Company{id: id, name: name}}

      _invalid ->
        {:error, Error.invalid_response(:mapping)}
    end
  end

  defp map_company(_identity), do: {:error, Error.invalid_response(:mapping)}

  defp map_people(employments) do
    if Enum.all?(employments, &is_map/1) do
      {people, warnings} =
        employments
        |> Enum.with_index()
        |> Enum.reduce({[], []}, fn {employment, index}, {people, warnings} ->
          case map_person(employment, index) do
            {:ok, person, person_warnings} ->
              {[person | people], Enum.reverse(person_warnings, warnings)}

            {:skip, warning} ->
              {people, [warning | warnings]}
          end
        end)

      {:ok, {Enum.reverse(people), Enum.reverse(warnings)}}
    else
      {:error, Error.invalid_response(:mapping)}
    end
  end

  defp map_person(employment, index) do
    case optional_string(employment["id"]) do
      nil ->
        {:skip, %{code: "missing_id", index: index}}

      id ->
        {name, warnings} = person_name(employment["full_name"], id)

        person = %Person{
          id: id,
          name: name,
          title: optional_string(employment["job_title"]),
          department:
            summary(
              optional_string(employment["department_id"]),
              optional_string(employment["department"])
            ),
          manager:
            summary(
              optional_string(employment["manager_employment_id"]),
              optional_string(employment["manager"])
            ),
          status: optional_string(employment["status"]),
          employment_type: optional_string(employment["type"]),
          employment_model: optional_string(employment["employment_model"])
        }

        {:ok, person, warnings}
    end
  end

  defp person_name(value, employment_id) do
    case optional_string(value) do
      nil ->
        {"Unknown employee", [%{code: "missing_name", employment_id: employment_id}]}

      name ->
        {name, []}
    end
  end

  defp summary(nil, nil), do: nil
  defp summary(id, name), do: %{id: id, name: name}

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(_value), do: nil
end
