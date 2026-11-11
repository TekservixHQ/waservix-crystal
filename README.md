# waservix (Crystal)

[![tests](https://github.com/TekservixHQ/waservix-crystal/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/waservix-crystal/actions/workflows/tests.yml)

**WAservix WhatsApp API Gateway** - official Crystal client (shard): send WhatsApp messages from your own number. By Tekservix.

Crystal shard for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and gives you a REST API to send text, images, documents, locations and polls, with webhooks for incoming messages.

No dependencies beyond the Crystal standard library.

## Install

Add to `shard.yml`:

```yaml
dependencies:
  waservix:
    github: TekservixHQ/waservix-crystal
```

then run `shards install`.

## Usage

You need a Tekservix account with WAservix and your number's API key (Devices in the dashboard). Keep it on your server.

```crystal
require "waservix"

wa = WAservix::Client.new(ENV["WASERVIX_KEY"])

res = wa.send_text("+15551234567", "Hello Aline, your order is ready")
res["msgId"]   # => 58213 (status "in_progress")

wa.send_image("+15551234567", "https://example.com/product.jpg", "Back in stock")
wa.send_document("+15551234567", "https://example.com/inv-1042.pdf", "Invoice-1042.pdf", "Your invoice")
wa.send_location("+15551234567", -1.9441, 30.0619, "Our shop")
wa.send_message("120363040000000000@g.us", {"text" => JSON::Any.new("Team meeting at 3pm")})

wa.get_message_info(58213)       # queued, sent, delivered, read, played or failed
wa.on_whatsapp("+15551234567")   # {"exists": true, "jid": ...}
wa.get_status                    # {"status": "connected"}
wa.list_groups
wa.request("GET", "/contacts")   # any other endpoint
```

Failed calls raise `WAservix::Error` with `status`, `message`, `errors`, `body` and `retry_after`. A 503 means the number is reconnecting.

Webhooks carry `X-Webhook-Signature`, which equals your number's webhook secret: check it with `WAservix.verify_webhook(signature, secret)`.

WAservix is not Meta's official WhatsApp Business Platform: WhatsApp's spam rules apply to your number, so only message people who expect to hear from you.

## More from Tekservix

- [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) ([Crystal shard](https://github.com/TekservixHQ/smsgora-crystal))
- [AI Sales Agent](https://tekservix.com/ai-sales-agent) and [Website to App](https://tekservix.com/mobile-apps)
- WAservix libraries for many more languages: [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
