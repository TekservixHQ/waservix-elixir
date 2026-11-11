# WAservix

[![Hex.pm](https://img.shields.io/hexpm/v/waservix.svg)](https://hex.pm/packages/waservix)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/waservix)
[![tests](https://github.com/TekservixHQ/waservix-elixir/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/waservix-elixir/actions/workflows/tests.yml)

**WAservix WhatsApp API Gateway** - official Elixir client: send WhatsApp messages from your own number. By Tekservix.

Elixir client for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and gives you a REST API to send text, images, video, audio, documents, locations, polls and more, with webhooks for incoming messages and status updates.

- Built on [Req](https://hex.pm/packages/req); works in Phoenix, Oban jobs, LiveView and scripts
- Plain `{:ok, data}` / `{:error, %WAservix.Error{}}` results
- Webhook check built in

## Installation

Add `waservix` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:waservix, "~> 1.0"}
  ]
end
```

## Quick start

Copy your device's API key from the WAservix dashboard (Devices -> API key) and keep it on your server.

```elixir
client = WAservix.new(System.fetch_env!("WASERVIX_KEY"))

{:ok, %{"msgId" => id, "status" => "in_progress"}} =
  WAservix.send_text(client, "+15551234567", "Hello Aline, your order is ready")
```

## Sending

Messages are queued and sent one at a time per number, so each call returns right away with `"status" => "in_progress"` and a `msgId`.

```elixir
# Image with caption
WAservix.send_image(client, "+15551234567", "https://example.com/product.jpg", caption: "Back in stock")

# Document
WAservix.send_document(client, "+15551234567", "https://example.com/inv-1042.pdf",
  file_name: "Invoice-1042.pdf",
  caption: "Your invoice"
)

# Location
WAservix.send_location(client, "+15551234567", -1.9441, 30.0619, name: "Our shop")

# Anything the API supports, including groups (JID ending in @g.us)
WAservix.send_message(client, "120363040000000000@g.us", %{text: "Team meeting at 3pm"})
WAservix.send_message(client, "+15551234567", %{poll: %{name: "Lunch?", options: ["Pizza", "Sushi"]}})
```

## Status, contacts and groups

```elixir
{:ok, info} = WAservix.get_message_info(client, 58213)    # queued, sent, delivered, read, played or failed
{:ok, check} = WAservix.on_whatsapp(client, "+15551234567") # %{"exists" => true, "jid" => "..."}
{:ok, conn} = WAservix.get_status(client)                 # %{"status" => "connected"}

WAservix.edit_message(client, 58213, "Corrected text")    # own text messages, about 15 minutes
{:ok, groups} = WAservix.list_groups(client)
```

Anything else in the [API reference](https://tekservix.com/waservix/docs/) is one call away:

```elixir
WAservix.request(client, :post, "/messages/read", %{msgId: "3EB0X123456789"})
```

## Webhooks

Set a webhook URL and events for the number in the dashboard. Each request carries `X-Webhook-Signature`, which equals the device's webhook secret. Phoenix example:

```elixir
def wa_webhook(conn, params) do
  signature = conn |> get_req_header("x-webhook-signature") |> List.first()

  if WAservix.verify_webhook(signature, System.fetch_env!("WASERVIX_WEBHOOK_SECRET")) do
    if params["event"] == "messages.received" do
      m = params["data"]["messages"]
      # m["key"]["cleanedSenderPn"], m["messageBody"]: enqueue an Oban job
    end

    send_resp(conn, 200, "ok")
  else
    send_resp(conn, 401, "bad signature")
  end
end
```

## Errors

Failed calls return `{:error, %WAservix.Error{}}` with `status`, `message`, field `errors` and, on 429, `retry_after` in seconds. A 503 means the device is reconnecting: retry shortly.

Never put the key in a browser or mobile app: anyone could read it. Call the API from your server.

## Migrating from WaSender

WAservix accepts the same `/send-message` body and webhook fields as WaSender, so most integrations switch by changing the base URL and key. See the [compatibility notes](https://tekservix.com/waservix/docs/).

## Use it responsibly

WAservix is not Meta's official WhatsApp Business Platform. There's no business verification and no per-conversation fee, but WhatsApp's spam rules apply to your number directly. Message people who expect to hear from you, warm up new numbers slowly and keep the built-in account protection on.

## More from Tekservix

- [SMS Gora SMS Gateway](https://tekservix.com/smsgora/): send SMS through your own Android phones ([`{:smsgora, "~> 1.0"}`](https://hex.pm/packages/smsgora))
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- WAservix is also on npm, PyPI, Packagist, Go, Maven (JitPack), NuGet, RubyGems, Swift, crates.io, pub.dev and JSR: see [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
