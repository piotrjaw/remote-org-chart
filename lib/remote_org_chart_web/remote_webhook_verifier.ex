defmodule RemoteOrgChartWeb.RemoteWebhookVerifier do
  @moduledoc false

  @spec valid?(binary(), binary() | nil, binary() | nil, binary() | nil) :: boolean()
  def valid?(body, timestamp, signature, signing_key)
      when is_binary(body) and is_binary(timestamp) and is_binary(signature) and
             is_binary(signing_key) do
    expected =
      :crypto.mac(:hmac, :sha256, signing_key, body <> ":" <> timestamp)
      |> Base.encode16(case: :lower)

    fresh?(timestamp) and byte_size(signature) == byte_size(expected) and
      Plug.Crypto.secure_compare(signature, expected)
  end

  def valid?(_body, _timestamp, _signature, _signing_key), do: false

  defp fresh?(timestamp) do
    with true <- byte_size(timestamp) == 13,
         {milliseconds, ""} <- Integer.parse(timestamp) do
      abs(System.system_time(:millisecond) - milliseconds) <= 300_000
    else
      _ -> false
    end
  end
end
