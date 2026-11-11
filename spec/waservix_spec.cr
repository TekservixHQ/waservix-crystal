require "spec"
require "http/server"
require "../src/waservix"

record Seen, method : String, resource : String, auth : String?, body : JSON::Any?

LAST = Channel(Seen).new(100)

SERVER = HTTP::Server.new do |ctx|
  req = ctx.request
  raw = req.body.try(&.gets_to_end) || ""
  LAST.send(Seen.new(req.method, req.resource, req.headers["Authorization"]?, raw.empty? ? nil : JSON.parse(raw)))
  ctx.response.content_type = "application/json"
  if req.path.starts_with?("/down")
    ctx.response.status_code = 503
    ctx.response.print %({"success":false,"message":"Device reconnecting"})
  elsif req.path.starts_with?("/soft")
    ctx.response.print %({"success":false,"message":"Invalid number"})
  else
    ctx.response.print %({"success":true,"data":{"msgId":58213,"status":"in_progress"}})
  end
end
ADDR = SERVER.bind_tcp("127.0.0.1", 0)
spawn { SERVER.listen }

def client(prefix = "/api")
  WAservix::Client.new("wpk_test", base_url: "http://127.0.0.1:#{ADDR.port}#{prefix}")
end

describe WAservix do
  it "sends text" do
    res = client.send_text("+1555", "hi")
    res["msgId"].as_i.should eq 58213
    seen = LAST.receive
    seen.resource.should eq "/api/send-message"
    seen.auth.should eq "Bearer wpk_test"
    seen.body.not_nil!.as_h.should eq({"to" => JSON::Any.new("+1555"), "text" => JSON::Any.new("hi")})
  end

  it "sends media and builds paths" do
    c = client
    c.send_image("+1", "https://x/y.jpg")
    body = LAST.receive.body.not_nil!.as_h
    body["imageUrl"].as_s.should eq "https://x/y.jpg"
    body.has_key?("text").should be_false
    c.send_document("+1", "https://x/a.pdf", "a.pdf", "c")
    LAST.receive.body.not_nil!["fileName"].as_s.should eq "a.pdf"
    c.send_location("+1", -1.9441, 30.0619, "Shop")
    LAST.receive.body.not_nil!["location"]["name"].as_s.should eq "Shop"
    c.get_message_info(5)
    LAST.receive.resource.should eq "/api/messages/5/info"
    c.edit_message(5, "t")
    LAST.receive.method.should eq "PUT"
    c.on_whatsapp("+1555")
    LAST.receive.resource.should eq "/api/on-whatsapp/%2B1555"
    c.get_group_metadata("1203@g.us")
    LAST.receive.resource.should eq "/api/groups/1203%40g.us/metadata"
    c.connect_session(3)
    LAST.receive.body.not_nil!["method"].as_s.should eq "qr"
    c.connect_session(3, "+1555")
    LAST.receive.body.not_nil!["phone"].as_s.should eq "+1555"
    expect_raises(ArgumentError) { c.send_text("", "x") }
    expect_raises(ArgumentError) { WAservix::Client.new("") }
  end

  it "raises API errors" do
    err = expect_raises(WAservix::Error) { client("/down").get_status }
    LAST.receive
    err.status.should eq 503
    err.message.should eq "Device reconnecting"
    err2 = expect_raises(WAservix::Error) { client("/soft").send_text("+1", "x") }
    LAST.receive
    err2.message.should eq "Invalid number"
  end

  it "verifies webhooks" do
    WAservix.verify_webhook("abc", "abc").should be_true
    WAservix.verify_webhook("abd", "abc").should be_false
    WAservix.verify_webhook("abcd", "abc").should be_false
    WAservix.verify_webhook(nil, "abc").should be_false
  end
end
