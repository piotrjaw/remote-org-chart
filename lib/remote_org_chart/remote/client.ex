defmodule RemoteOrgChart.Remote.Client do
  @moduledoc """
  Fetches company identity and every Remote bulk-employment page.
  """

  @behaviour RemoteOrgChart.Remote.Source

  alias RemoteOrgChart.Remote.Error

  @identity_path "/v1/identity/current"
  @employments_path "/v1/employments/bulk"
  @page_limit 100

  @impl true
  def fetch(options \\ []) do
    request = Keyword.get_lazy(options, :req, &build_request/0)

    with {:ok, identity} <- request_json(request, @identity_path),
         {:ok, company_id} <- company_id(identity),
         {:ok, employments, page_count} <-
           fetch_employment_pages(request, company_id, nil, MapSet.new(), [], 0) do
      {:ok,
       %{
         identity: identity,
         employments: employments,
         page_count: page_count
       }}
    end
  end

  defp build_request do
    Req.new(
      base_url: Application.fetch_env!(:remote_org_chart, :remote_api_base_url),
      auth: {:bearer, Application.fetch_env!(:remote_org_chart, :remote_api_token)},
      receive_timeout: 5_000,
      connect_options: [timeout: 3_000],
      retry: false
    )
  end

  defp company_id(%{"data" => %{"company" => %{"id" => id}}}) when is_binary(id) do
    case String.trim(id) do
      "" -> {:error, Error.invalid_response(:identity)}
      company_id -> {:ok, company_id}
    end
  end

  defp company_id(_identity), do: {:error, Error.invalid_response(:identity)}

  defp fetch_employment_pages(
         request,
         company_id,
         cursor,
         seen_cursors,
         accumulated,
         page_count
       ) do
    params =
      [company_id: company_id, limit: @page_limit]
      |> maybe_add_cursor(cursor)

    with {:ok, page} <- request_json(request, @employments_path, params),
         {:ok, records, next_cursor} <- employment_page(page),
         {:ok, seen_cursors} <- remember_cursor(next_cursor, seen_cursors) do
      accumulated = Enum.reverse(records, accumulated)
      page_count = page_count + 1

      case next_cursor do
        nil ->
          {:ok, Enum.reverse(accumulated), page_count}

        next_cursor ->
          fetch_employment_pages(
            request,
            company_id,
            next_cursor,
            seen_cursors,
            accumulated,
            page_count
          )
      end
    end
  end

  defp maybe_add_cursor(params, nil), do: params
  defp maybe_add_cursor(params, cursor), do: Keyword.put(params, :cursor, cursor)

  defp employment_page(%{"data" => records, "next_cursor" => next_cursor})
       when is_list(records) and (is_binary(next_cursor) or is_nil(next_cursor)) do
    if Enum.all?(records, &is_map/1) and next_cursor != "" do
      {:ok, records, next_cursor}
    else
      {:error, Error.invalid_response(:employments)}
    end
  end

  defp employment_page(_page), do: {:error, Error.invalid_response(:employments)}

  defp remember_cursor(nil, seen_cursors), do: {:ok, seen_cursors}

  defp remember_cursor(cursor, seen_cursors) do
    if MapSet.member?(seen_cursors, cursor) do
      {:error, Error.invalid_response(:pagination)}
    else
      {:ok, MapSet.put(seen_cursors, cursor)}
    end
  end

  defp request_json(request, path, params \\ []) do
    case Req.get(request, url: path, params: params) do
      {:ok, %Req.Response{status: status, body: body}}
      when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, Error.authentication(:http)}

      {:ok, %Req.Response{status: 429} = response} ->
        {:error, Error.temporary(:http, retry_after(response))}

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        {:error, Error.temporary(:http)}

      {:error, %Req.TransportError{}} ->
        {:error, Error.temporary(:http)}

      _failure ->
        {:error, Error.invalid_response(:http)}
    end
  end

  defp retry_after(response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _rest] ->
        case Integer.parse(value) do
          {seconds, ""} when seconds in 0..300 -> seconds
          _invalid -> nil
        end

      [] ->
        nil
    end
  end
end
