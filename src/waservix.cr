require "crypto/subtle"
require "http/client"
require "json"
require "uri"

# Crystal client for the WAservix WhatsApp API Gateway (https://tekservix.com/waservix/).
#
# ```
# require "waservix"
# wa = WAservix::Client.new(ENV["WASERVIX_KEY"])
# res = wa.send_text("+15551234567", "Hello Aline, your order is ready")
# res["msgId"] # => 58213
# ```
#
# Needs a Tekservix account with WAservix and your number's API key. Keep it on your server.
module WAservix
  VERSION          = "1.0.0"
  DEFAULT_BASE_URL = "https://tekservix.com/waservix/api"

  # Raised when the API answers with an error. A 503 means the number is reconnecting.
  class Error < Exception
    getter status : Int32
    getter errors : JSON::Any?
    getter body : String
    getter retry_after : Float64?

    def initialize(message : String, @status : Int32, @errors : JSON::Any? = nil, @body : String = "", @retry_after : Float64? = nil)
      super(message)
    end
  end

  class Client
    getter base_url : String

    def initialize(@api_key : String, base_url : String = DEFAULT_BASE_URL, @timeout : Time::Span = 30.seconds)
      raise ArgumentError.new("WAservix: api_key is required (Devices -> API key in the WAservix dashboard)") if @api_key.empty?
      @base_url = base_url.rstrip('/')
    end

    # Call any documented endpoint, e.g. `request("GET", "/groups")`. Returns the `data` field.
    def request(method : String, path : String, body = nil) : JSON::Any
      headers = HTTP::Headers{
        "Authorization" => "Bearer #{@api_key}",
        "Accept"        => "application/json",
        "User-Agent"    => "waservix-crystal/#{VERSION}",
      }
      payload = nil
      unless body.nil?
        headers["Content-Type"] = "application/json"
        payload = body.to_json
      end

      uri = URI.parse(@base_url + path)
      response = begin
        client = HTTP::Client.new(uri)
        client.connect_timeout = @timeout
        client.read_timeout = @timeout
        client.exec(method.upcase, uri.request_target, headers, payload)
      rescue ex : IO::Error | Socket::Error
        raise Error.new("WAservix: request failed (#{ex.message})", 0)
      end

      text = response.body
      data = text.empty? ? nil : (JSON.parse(text) rescue nil)
      hash = data.try &.as_h?
      failed = hash && hash["success"]? == JSON::Any.new(false)
      if response.status_code >= 400 || failed
        message = hash.try(&.["message"]?).try(&.as_s?) || "HTTP #{response.status_code}"
        retry = response.headers["Retry-After"]?.try &.to_f?
        raise Error.new(message, response.status_code, hash.try(&.["errors"]?), text, retry)
      end
      return hash["data"] if hash && hash.has_key?("data")
      data || JSON::Any.new(nil)
    end

    # Send any message type to a number or group JID (`...@g.us`). Field names follow the API:
    # text, imageUrl, videoUrl, audioUrl, documentUrl, fileName, stickerUrl, contact, location,
    # poll, replyTo, mentions, viewOnce. Returns `{"msgId", "jid", "status": "in_progress"}`.
    def send_message(to : String, fields : Hash(String, JSON::Any)) : JSON::Any
      raise ArgumentError.new(%(send_message: "to" is required (international number or group JID))) if to.empty?
      body = fields.reject { |_, v| v.raw.nil? }
      body["to"] = JSON::Any.new(to)
      request("POST", "/send-message", body)
    end

    def send_text(to : String, text : String) : JSON::Any
      send_message(to, {"text" => JSON::Any.new(text)})
    end

    def send_image(to : String, image_url : String, caption : String? = nil) : JSON::Any
      send_message(to, {"imageUrl" => JSON::Any.new(image_url), "text" => JSON::Any.new(caption)})
    end

    def send_document(to : String, document_url : String, file_name : String? = nil, caption : String? = nil) : JSON::Any
      send_message(to, {"documentUrl" => JSON::Any.new(document_url), "fileName" => JSON::Any.new(file_name), "text" => JSON::Any.new(caption)})
    end

    def send_location(to : String, latitude : Float64, longitude : Float64, name : String? = nil) : JSON::Any
      location = {"latitude" => JSON::Any.new(latitude), "longitude" => JSON::Any.new(longitude)}
      location["name"] = JSON::Any.new(name) if name
      send_message(to, {"location" => JSON::Any.new(location)})
    end

    # Status: queued, sent, delivered, read, played or failed.
    def get_message_info(id) : JSON::Any
      request("GET", "/messages/#{esc(id)}/info")
    end

    # Edit one of your own text messages (about 15 minutes after sending).
    def edit_message(id, text : String) : JSON::Any
      request("PUT", "/messages/#{esc(id)}", {"text" => text})
    end

    def delete_message(id) : JSON::Any
      request("DELETE", "/messages/#{esc(id)}")
    end

    def resend_message(id) : JSON::Any
      request("POST", "/messages/#{esc(id)}/resend")
    end

    # Is this number on WhatsApp? Returns `{"exists": true/false, "jid": ...}`.
    def on_whatsapp(phone : String) : JSON::Any
      request("GET", "/on-whatsapp/#{esc(phone)}")
    end

    # connected, connecting, need_scan, disconnected, logged_out or expired.
    def get_status : JSON::Any
      request("GET", "/status")
    end

    def get_user : JSON::Any
      request("GET", "/user")
    end

    def list_contacts : JSON::Any
      request("GET", "/contacts")
    end

    def get_contact(phone : String) : JSON::Any
      request("GET", "/contacts/#{esc(phone)}")
    end

    def save_contact(phone : String, name : String) : JSON::Any
      request("PUT", "/contacts", {"phone" => phone, "name" => name})
    end

    def list_groups : JSON::Any
      request("GET", "/groups")
    end

    def get_group_metadata(group_jid : String) : JSON::Any
      request("GET", "/groups/#{esc(group_jid)}/metadata")
    end

    # Sessions need a personal access token, not a device key.
    def list_sessions : JSON::Any
      request("GET", "/whatsapp-sessions")
    end

    def get_session(id) : JSON::Any
      request("GET", "/whatsapp-sessions/#{esc(id)}")
    end

    def create_session(params : Hash(String, JSON::Any) = {} of String => JSON::Any) : JSON::Any
      request("POST", "/whatsapp-sessions", params)
    end

    # Connect by QR code, or by pairing code when `phone` is given.
    def connect_session(id, phone : String? = nil) : JSON::Any
      body = phone ? {"method" => "code", "phone" => phone} : {"method" => "qr"}
      request("POST", "/whatsapp-sessions/#{esc(id)}/connect", body)
    end

    def get_session_qr_code(id) : JSON::Any
      request("GET", "/whatsapp-sessions/#{esc(id)}/qrcode")
    end

    private def esc(value) : String
      URI.encode_path_segment(value.to_s).gsub("+", "%2B").gsub("@", "%40")
    end
  end

  # Constant-time check of the X-Webhook-Signature header against your number's webhook secret.
  def self.verify_webhook(signature : String?, secret : String) : Bool
    return false if signature.nil? || signature.empty? || secret.empty?
    Crypto::Subtle.constant_time_compare(signature, secret)
  end
end
