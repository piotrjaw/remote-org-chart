defmodule RemoteOrgChartWeb.RemoteWebhookAuthentication do
  @moduledoc false

  import Plug.Conn

  alias RemoteOrgChartWeb.RemoteWebhookVerifier

  @max_body_length 1_000_000

  def init(options), do: options

  def call(%{method: "POST", request_path: "/api/webhooks/remote"} = conn, _options) do
    case read_body(conn, length: @max_body_length, read_length: @max_body_length) do
      {:ok, body, conn} -> authenticate(conn, body)
      {:more, _partial_body, conn} -> reject(conn)
      {:error, _reason} -> reject(conn)
    end
  end

  def call(conn, _options), do: conn

  defp authenticate(conn, body) do
    timestamp = header(conn, "x-remote-timestamp")
    signature = header(conn, "x-remote-signature")
    signing_key = Application.get_env(:remote_org_chart, :remote_webhook_signing_key)

    if RemoteWebhookVerifier.valid?(body, timestamp, signature, signing_key) do
      conn
      |> assign(:remote_webhook_verified, true)
      |> assign(:remote_webhook_signature, signature)
      |> delete_req_header("content-type")
    else
      reject(conn)
    end
  end

  defp reject(conn) do
    body =
      Phoenix.json_library().encode_to_iodata!(%{error: %{code: "invalid_webhook_signature"}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, body)
    |> halt()
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value] -> value
      _other -> nil
    end
  end
end
