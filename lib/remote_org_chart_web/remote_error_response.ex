defmodule RemoteOrgChartWeb.RemoteErrorResponse do
  @moduledoc """
  Maps typed Remote failures to stable, non-sensitive API responses.
  """

  import Plug.Conn

  alias RemoteOrgChart.Remote.Error

  @spec send_response(Plug.Conn.t(), Error.t()) :: Plug.Conn.t()
  def send_response(conn, %Error{} = error) do
    {status, code} = status_and_code(error.kind)

    response_error =
      if error.kind == :internal do
        %{code: code, request_id: conn.assigns[:request_id]}
      else
        %{code: code}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> maybe_put_retry_after(error)
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: response_error})
  end

  defp status_and_code(:authentication), do: {:bad_gateway, "remote_authentication_failed"}
  defp status_and_code(:temporary), do: {:service_unavailable, "remote_temporarily_unavailable"}
  defp status_and_code(:invalid_response), do: {:bad_gateway, "invalid_remote_response"}
  defp status_and_code(:internal), do: {:internal_server_error, "internal_error"}

  defp maybe_put_retry_after(conn, %Error{
         kind: :temporary,
         retry_after: retry_after
       })
       when retry_after in 0..300 do
    put_resp_header(conn, "retry-after", Integer.to_string(retry_after))
  end

  defp maybe_put_retry_after(conn, _error), do: conn
end
