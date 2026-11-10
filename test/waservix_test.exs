defmodule WAservixTest do
  use ExUnit.Case, async: true

  @ok ~s({"success":true,"data":{"msgId":58213,"status":"in_progress"}})

  # Req runs the plug in the test process, so each request is sent back to us as a message.
  defp client(status \\ 200, reply \\ @ok) do
    test_pid = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, %{
        method: conn.method,
        path: conn.request_path,
        auth: Plug.Conn.get_req_header(conn, "authorization") |> List.first(),
        body: if(body == "", do: nil, else: Jason.decode!(body))
      })

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, reply)
    end

    WAservix.new("wpk_test", base_url: "https://example.test/api", req_options: [plug: plug])
  end

  test "send_text" do
    assert {:ok, %{"msgId" => 58213, "status" => "in_progress"}} =
             WAservix.send_text(client(), "+1555", "hi")

    assert_received %{
      method: "POST",
      path: "/api/send-message",
      auth: "Bearer wpk_test",
      body: body
    }

    assert body == %{"to" => "+1555", "text" => "hi"}
  end

  test "media and paths" do
    c = client()

    {:ok, _} = WAservix.send_image(c, "+1", "https://x/y.jpg")
    assert_received %{body: %{"to" => "+1", "imageUrl" => "https://x/y.jpg"} = body}
    refute Map.has_key?(body, "text")

    {:ok, _} =
      WAservix.send_document(c, "+1", "https://x/a.pdf", file_name: "a.pdf", caption: "c")

    assert_received %{body: %{"fileName" => "a.pdf", "text" => "c"}}

    {:ok, _} = WAservix.send_location(c, "+1", -1.9441, 30.0619, name: "Shop")
    assert_received %{body: %{"location" => %{"name" => "Shop"}}}

    {:ok, _} = WAservix.get_message_info(c, 5)
    assert_received %{path: "/api/messages/5/info"}

    {:ok, _} = WAservix.edit_message(c, 5, "t")
    assert_received %{method: "PUT", body: %{"text" => "t"}}

    {:ok, _} = WAservix.on_whatsapp(c, "+1555")
    assert_received %{path: "/api/on-whatsapp/%2B1555"}

    {:ok, _} = WAservix.get_group_metadata(c, "1203@g.us")
    assert_received %{path: "/api/groups/1203%40g.us/metadata"}

    {:ok, _} = WAservix.connect_session(c, 3)
    assert_received %{body: %{"method" => "qr"}}

    {:ok, _} = WAservix.connect_session(c, 3, phone: "+1555")
    assert_received %{body: %{"method" => "code", "phone" => "+1555"}}

    assert_raise ArgumentError, fn -> WAservix.send_text(c, "", "x") end
  end

  test "API errors" do
    assert {:error, %WAservix.Error{status: 503, message: "Device reconnecting"}} =
             WAservix.get_status(
               client(503, ~s({"success":false,"message":"Device reconnecting"}))
             )

    assert {:error, %WAservix.Error{status: 200, message: "Invalid number"}} =
             WAservix.send_text(
               client(200, ~s({"success":false,"message":"Invalid number"})),
               "+1",
               "x"
             )

    assert_raise ArgumentError, fn -> WAservix.new("") end
  end

  test "verify_webhook" do
    assert WAservix.verify_webhook("abc", "abc")
    refute WAservix.verify_webhook("abd", "abc")
    refute WAservix.verify_webhook("abcd", "abc")
    refute WAservix.verify_webhook(nil, "abc")
  end
end
