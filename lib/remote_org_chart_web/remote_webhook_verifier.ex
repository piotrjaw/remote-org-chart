defmodule RemoteOrgChartWeb.RemoteWebhookVerifier do
  @moduledoc false

  @spec valid?(binary(), binary() | nil, binary() | nil, binary() | nil) :: boolean()
  def valid?(body, timestamp, signature, signing_key)
      when is_binary(body) and is_binary(timestamp) and is_binary(signature) and
             is_binary(signing_key) do
    expected =
      :crypto.mac(:hmac, :sha256, signing_key, body <> ":" <> timestamp)
      |> Base.encode16(case: :lower)

    byte_size(signature) == byte_size(expected) and
      Plug.Crypto.secure_compare(signature, expected)
  end

  def valid?(_body, _timestamp, _signature, _signing_key), do: false
end
