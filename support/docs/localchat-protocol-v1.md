# LocalChat protocol v1

LocalChat extends LocalSend v2.2 on the same HTTPS listener. Discovery still uses
UDP 53317 and announces the actual HTTP port. Original LocalSend file routes remain
available. These chat routes require an authenticated TLS client certificate even
when browser file sharing makes client certificates optional on other routes.
Cleartext HTTP receives 403. Clients must pin the target's SHA-256 DER certificate
fingerprint during TLS negotiation, before transmitting any application data.
Neither an IP address nor a fingerprint supplied in JSON establishes identity.

All JSON keys are camelCase. IDs are canonical lowercase, hyphenated RFC 4122
UUID v4 strings. Unknown versions and invalid IDs receive 400. No account, central
server or public signaling service is involved. The v3 client backend does not
implement this extension.

## Routes

`GET /api/localchat/v1/capabilities` returns 200:

```json
{"version":1,"features":["text","file-ref"],"maxTextBytes":32768}
```

`POST /api/localchat/v1/invitations`:

```json
{"version":1,"invitationId":"cdff33b3-1f7d-4ce1-9c31-6b7818a504bf"}
```

The application persists the invitation before replying. Pending invitations
return 202; accepted/rejected invitations return 200. A repeated invitation keeps
the original decision. Receiving permission and the peer's receiving permission
are independent. Invitations do not automatically authorize file reception.

```json
{"invitationId":"cdff33b3-1f7d-4ce1-9c31-6b7818a504bf","status":"pending"}
```

`GET /api/localchat/v1/invitations/{invitationId}` returns the same shape with 200,
including when pending. Status is one of `pending`, `accepted`, `rejected` and is
visible only to the certificate identity that initiated this invitation. The
caller must match the response ID to its own outstanding invitation.

`POST /api/localchat/v1/messages`:

```json
{"version":1,"messageId":"eb48b9c0-2af0-448b-9d39-e88b3ac4e142","sentAtMs":1792396800000,"text":"你好 👋"}
```

Text is limited to 32768 UTF-8 bytes, must contain non-whitespace, and is stored
without trimming. `sentAtMs` is a signed 64-bit Unix millisecond timestamp; local
database sequence numbers determine history order. The total raw JSON body is
limited to 262144 bytes, including chunked requests.

Only a successful durable commit permits a 201 acknowledgment:

```json
{"messageId":"eb48b9c0-2af0-448b-9d39-e88b3ac4e142","duplicate":false}
```

A retry with the same sender certificate, ID, text and timestamp returns 200 and
`duplicate:true`. Reusing that key with different immutable content returns 409.
The client validates the ACK ID and verified target identity. Delivered means
committed at the receiving device, not read by a person. A lost ACK is retried
with the same ID. File completion is reported by the file transfer, never by a
text ACK. `file-ref` enables the prepare-upload association described by the
attachment extension; it does not replace the LocalSend file protocol.

## Errors and resource limits

Errors have the form `{"message":"denied"}`. Codes: 400 malformed JSON/version/ID
or blank text; 403 certificate required or permission denied; 409 content
conflict; 413 text/body too large; 429 overloaded; 503 storage/responder unavailable
or an invalid application reply; 504 body/read or application response timeout.
Unknown paths/methods return 404. Only an explicit unsupported/404 response can
classify a peer as lacking the extension; TLS/network failures cannot.

At most 64 chat requests globally and 8 per verified certificate may be in flight,
including across separate TCP connections. Body read and application response
each have a five-second deadline. A bounded event queue rejects overflow with 429
and never waits for the user to accept an invitation. Disconnect, timeout and
server shutdown release the request slot and invalidate its responder. Chat does
not occupy the single LocalSend file-receive slot.

Core tests use an in-memory application responder. Durable receipts require the
application database/controller integration; passing core protocol tests alone
does not demonstrate durable end-to-end delivery.

## File association (`file-ref`)

Only send this optional field to a TLS peer that advertises `file-ref` and has
granted chat permission. Ordinary LocalSend transfers omit the entire field:

```json
{"localchat":{"messageId":"eb48b9c0-2af0-448b-9d39-e88b3ac4e142","transferId":"cdff33b3-1f7d-4ce1-9c31-6b7818a504bf","attachments":{"wire-file-id":"843b7a1a-6677-4564-a225-83f0bde16349"}}}
```

This is added to the existing v2 `prepare-upload` JSON beside `info` and `files`.
Message, transfer and attachment IDs are canonical UUID v4. The map contains
exactly one unique stable attachment ID for each of 1–1000 offered wire file IDs;
each wire key must match its FileDto.id. All later uploads and cancellation of
this receive session require the same actual client certificate as preparation.
Self-reported `info.fingerprint` cannot assign a conversation or authorize access.

Both applications persist local session/file ownership. The sender stores the
receiver's session ID after preparation. Missing file tokens mean individual
rejection; 204 means no files accepted. Per-file upload/save events determine
completion, cancellation or failure. A session-end event or text ACK never marks
all files complete. In-flight writes may finish after cancellation and report
their actual result. Interrupted cards survive restart as failed; sending again
creates a new message rather than claiming resumable transfers.

Outgoing “File sent” means the existing LocalSend upload succeeded. Incoming
“File saved” is recorded only after local file/gallery post-processing succeeds.
The existing protocol does not provide a separate remote gallery-save receipt.
