# Chat attachments (phone and desktop)

## Upload

`POST /api/uploads` with the session token (`Authorization: Bearer …` / `X-Neovarch-Session-Token` / `?token=`):

- multipart/form-data: a `file` field plus an optional `session_id` field (or `?session_id=`), **or**
- a raw body with `?filename=…&session_id=…` and a `Content-Type`.

The size limit is 25 MB (HTTP 413 above it). Files are stored as `~/.neovarch/uploads/<session>/<id>-<name>`. The response is:

```json
{"id": "a1b2c3d4e5f6", "name": "foto.jpg", "mime": "image/jpeg", "size": 123456,
 "kind": "image", "session_id": "…", "path": "/home/u/.neovarch/uploads/…", "url": "/api/uploads/a1b2c3d4e5f6"}
```

For clients without multipart there is a chunked JSON-RPC over the existing WebSocket: `attachment.upload_chunk {session_id, filename, mime, data: <base64>, upload_id?, final?}`. The first call returns `upload_id`. Later calls send it back, and the final call returns the stored upload.

Other routes:

- `GET /api/uploads/{id}` returns the bytes (`?download=1` for `Content-Disposition: attachment`).
- `GET /api/uploads/{id}/meta` returns the metadata.
- `GET /api/uploads?session_id=` lists a session's uploads.
- `DELETE /api/uploads/{id}` deletes one.
- `GET /api/fs/download?path=` is a binary download for any file, such as reports or artifacts (`?inline=1` to view in place).

## Sending

`prompt.submit {session_id, text, attachments: ["<id>", …]}`. `text` may be empty when there are attachments. The result echoes `attachments` and adds `notice` when images were sent to a model without vision.

- **Images** go to the model as OpenAI-compatible content parts (`{"type":"image_url","image_url":{"url":"data:image/…;base64,…"}}`) when the selected model accepts image input. Vision support is decided in this order:
  1. `model.vision: true|false` in config.yaml;
  2. `vision: true|false` on a custom endpoint;
  3. a known vision model name (gpt-4o/4.1/5, Claude 3+/4, Gemini, Qwen-VL, LLaVA, Pixtral, …).

  Without vision, the agent gets the image's file path, and the client gets a clear notice (the event `attachment.notice` and `notice` in the submit result). Images are re-sent only for the last 3 user turns that had them.
- **Other files** reach the agent as their path plus extracted text for txt/md/code (up to 20 000 characters) and PDF (via `pdftotext` when installed).
- Stored transcripts keep only a reference, never the bytes. `GET /api/sessions/{id}/messages` returns `attachments: [{id, name, mime, size, kind, url}]` on user messages, so clients can render bubbles and thumbnails.

## Desktop composer

The desktop composer stages attachments before `prompt.submit` with these RPCs, which the core now implements:

- `image.attach {session_id, path}` and `image.attach_bytes {session_id, content_base64, filename}` stage an image for the next submit;
- `image.detach {session_id, path}` removes a staged image;
- `file.attach {session_id, path | data_url, name}` returns `ref_text: "@file:<path>"`. The composer puts this ref in the prompt, and the core appends the file's text for the model.

Drag-drop and paste in the desktop composer use these RPCs, so images and files now work end to end.
