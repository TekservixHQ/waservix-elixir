defmodule WAservix do
  @moduledoc """
  Elixir client for the [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/).

  WAservix links your own WhatsApp number by QR code (the same way WhatsApp Web does) and
  gives you a REST API to send text, images, documents, locations, polls and more.

      client = WAservix.new(System.fetch_env!("WASERVIX_KEY"))
      {:ok, %{"msgId" => id, "status" => "in_progress"}} =
        WAservix.send_text(client, "+15551234567", "Hello Aline, your order is ready")

  Every function returns `{:ok, data}` (the decoded `data` field of the answer) or
  `{:error, %WAservix.Error{}}`. Keep the API key on your server.

  API reference: https://tekservix.com/waservix/docs/
  """

  defmodule Error do
    @moduledoc """
    Returned when the API answers with an error, or the request fails.

    `status` is the HTTP status (0 when the request never reached the API). A 503 means
    the device is reconnecting: retry shortly. `retry_after` is set after a 429.
    """
    defexception [:status, :message, :errors, :body, :retry_after]

    @type t :: %__MODULE__{
            status: non_neg_integer(),
            message: String.t(),
            errors: map() | nil,
            body: term(),
            retry_after: number() | nil
          }
  end

  @version Mix.Project.config()[:version]
  @default_base_url "https://tekservix.com/waservix/api"

  defstruct [:req]

  @typedoc "A client. Create one with `new/2` and reuse it."
  @type t :: %__MODULE__{req: Req.Request.t()}

  @typedoc "Result of every API call."
  @type result :: {:ok, term()} | {:error, Error.t()}

  @doc """
  Creates a client with a device API key (Devices -> API key), or a personal access token
  for session management.

  Options:

    * `:base_url` - change only for testing
    * `:receive_timeout` - milliseconds to wait for an answer (default 30_000)
    * `:req_options` - extra options passed to `Req.new/1` (proxy, plug for tests, ...)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(api_key, opts \\ []) when is_binary(api_key) do
    if api_key == "" do
      raise ArgumentError,
            "WAservix: api_key is required (Devices -> API key in the WAservix dashboard)"
    end

    req =
      Req.new(
        [
          base_url: String.trim_trailing(Keyword.get(opts, :base_url, @default_base_url), "/"),
          headers: [
            {"authorization", "Bearer " <> api_key},
            {"accept", "application/json"},
            {"user-agent", "waservix-elixir/#{@version}"}
          ],
          receive_timeout: Keyword.get(opts, :receive_timeout, 30_000),
          retry: false
        ] ++ Keyword.get(opts, :req_options, [])
      )

    %__MODULE__{req: req}
  end

  @doc """
  Calls any documented endpoint, e.g. `request(client, :get, "/groups")`.
  Returns the `data` field of the answer.
  """
  @spec request(t(), atom(), String.t(), map() | nil) :: result()
  def request(%__MODULE__{req: req}, method, path, body \\ nil) do
    opts = [method: method, url: path]
    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    case Req.request(req, opts) do
      {:ok, %Req.Response{status: status, body: body} = resp} ->
        handle(status, body, resp)

      {:error, exception} ->
        {:error,
         %Error{status: 0, message: "WAservix: request failed (#{Exception.message(exception)})"}}
    end
  end

  defp handle(status, body, resp) do
    map = if is_map(body), do: body, else: nil

    if status >= 400 or (map && map["success"] == false) do
      {:error,
       %Error{
         status: status,
         message: (map && is_binary(map["message"]) && map["message"]) || "HTTP #{status}",
         errors: map && map["errors"],
         body: body,
         retry_after: retry_after(resp)
       }}
    else
      {:ok, if(map && Map.has_key?(map, "data"), do: map["data"], else: body)}
    end
  end

  defp retry_after(resp) do
    case Req.Response.get_header(resp, "retry-after") do
      [value | _] ->
        case Float.parse(String.trim(value)) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Sends any message type to a number or group JID (`...@g.us`). `fields` uses the API names:
  `text`, `imageUrl`, `videoUrl`, `audioUrl`, `documentUrl`, `fileName`, `stickerUrl`,
  `contact`, `location`, `poll`, `replyTo`, `mentions`, `viewOnce`.

      WAservix.send_message(client, "120363040000000000@g.us", %{text: "Team meeting at 3pm"})
  """
  @spec send_message(t(), String.t(), map()) :: result()
  def send_message(client, to, fields) when is_map(fields) do
    if to in [nil, ""] do
      raise ArgumentError,
            "send_message: \"to\" is required (international number or group JID)"
    end

    body =
      fields
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("to", to)

    request(client, :post, "/send-message", body)
  end

  @doc "Sends a text message."
  @spec send_text(t(), String.t(), String.t()) :: result()
  def send_text(client, to, text), do: send_message(client, to, %{text: text})

  @doc "Sends an image by URL. Option: `:caption`."
  @spec send_image(t(), String.t(), String.t(), keyword()) :: result()
  def send_image(client, to, image_url, opts \\ []),
    do: send_message(client, to, %{imageUrl: image_url, text: opts[:caption]})

  @doc "Sends a document by URL. Options: `:file_name`, `:caption`."
  @spec send_document(t(), String.t(), String.t(), keyword()) :: result()
  def send_document(client, to, document_url, opts \\ []) do
    send_message(client, to, %{
      documentUrl: document_url,
      fileName: opts[:file_name],
      text: opts[:caption]
    })
  end

  @doc "Sends a location pin. Option: `:name`."
  @spec send_location(t(), String.t(), number(), number(), keyword()) :: result()
  def send_location(client, to, latitude, longitude, opts \\ []) do
    location =
      %{"latitude" => latitude, "longitude" => longitude}
      |> then(fn l -> if opts[:name], do: Map.put(l, "name", opts[:name]), else: l end)

    send_message(client, to, %{location: location})
  end

  @doc "Message status: queued, sent, delivered, read, played or failed."
  @spec get_message_info(t(), term()) :: result()
  def get_message_info(client, id), do: request(client, :get, "/messages/#{esc(id)}/info")

  @doc "Edits one of your own text messages (about 15 minutes after sending)."
  @spec edit_message(t(), term(), String.t()) :: result()
  def edit_message(client, id, text),
    do: request(client, :put, "/messages/#{esc(id)}", %{"text" => text})

  @doc "Deletes a message."
  @spec delete_message(t(), term()) :: result()
  def delete_message(client, id), do: request(client, :delete, "/messages/#{esc(id)}")

  @doc "Resends a failed message."
  @spec resend_message(t(), term()) :: result()
  def resend_message(client, id), do: request(client, :post, "/messages/#{esc(id)}/resend")

  @doc "Is this number on WhatsApp? Returns `{:ok, %{\"exists\" => true, \"jid\" => ...}}`."
  @spec on_whatsapp(t(), String.t()) :: result()
  def on_whatsapp(client, phone), do: request(client, :get, "/on-whatsapp/#{esc(phone)}")

  @doc "Connection status: connected, connecting, need_scan, disconnected, logged_out or expired."
  @spec get_status(t()) :: result()
  def get_status(client), do: request(client, :get, "/status")

  @doc "The linked WhatsApp account."
  @spec get_user(t()) :: result()
  def get_user(client), do: request(client, :get, "/user")

  @doc "Your contacts."
  @spec list_contacts(t()) :: result()
  def list_contacts(client), do: request(client, :get, "/contacts")

  @doc "One contact."
  @spec get_contact(t(), String.t()) :: result()
  def get_contact(client, phone), do: request(client, :get, "/contacts/#{esc(phone)}")

  @doc "Saves or renames a contact."
  @spec save_contact(t(), String.t(), String.t()) :: result()
  def save_contact(client, phone, name),
    do: request(client, :put, "/contacts", %{"phone" => phone, "name" => name})

  @doc "Groups the number belongs to."
  @spec list_groups(t()) :: result()
  def list_groups(client), do: request(client, :get, "/groups")

  @doc "Group name, participants and settings."
  @spec get_group_metadata(t(), String.t()) :: result()
  def get_group_metadata(client, group_jid),
    do: request(client, :get, "/groups/#{esc(group_jid)}/metadata")

  @doc "Sessions (need a personal access token, not a device key)."
  @spec list_sessions(t()) :: result()
  def list_sessions(client), do: request(client, :get, "/whatsapp-sessions")

  @doc "One session."
  @spec get_session(t(), term()) :: result()
  def get_session(client, id), do: request(client, :get, "/whatsapp-sessions/#{esc(id)}")

  @doc "Creates a session."
  @spec create_session(t(), map()) :: result()
  def create_session(client, params), do: request(client, :post, "/whatsapp-sessions", params)

  @doc "Connects a session by QR code, or by pairing code with `phone: \"+1555...\"`."
  @spec connect_session(t(), term(), keyword()) :: result()
  def connect_session(client, id, opts \\ []) do
    body =
      case opts[:phone] do
        nil -> %{"method" => "qr"}
        phone -> %{"method" => "code", "phone" => phone}
      end

    request(client, :post, "/whatsapp-sessions/#{esc(id)}/connect", body)
  end

  @doc "QR code for linking the number."
  @spec get_session_qr_code(t(), term()) :: result()
  def get_session_qr_code(client, id),
    do: request(client, :get, "/whatsapp-sessions/#{esc(id)}/qrcode")

  @doc """
  Constant-time check of the `X-Webhook-Signature` header against your device's webhook secret.

      WAservix.verify_webhook(get_req_header(conn, "x-webhook-signature") |> List.first(), secret)
  """
  @spec verify_webhook(String.t() | nil, String.t()) :: boolean()
  def verify_webhook(signature, secret)
      when is_binary(signature) and signature != "" and is_binary(secret) and secret != "" and
             byte_size(signature) == byte_size(secret) do
    signature
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(secret))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  def verify_webhook(_signature, _secret), do: false

  defp esc(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
end
