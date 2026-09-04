# Multimodal — what actually works

The model's `/v1/models` spec says `input_modalities: ["text"]`, but empirically **vision works** (with caveats). Audio, file, and video do not.

All findings here are verified against the live API (2026-05-22).

## Vision — partial support

`image_url` content blocks **work** for most image sources, despite what the model spec advertises.

### Verified working

| Source | Result |
|---|---|
| `placehold.co/100x100.png` | 200, model describes correctly |
| `placehold.co/200x200.jpg` | 200, model reads dimension text |
| `placehold.co/300x150` placeholder text | 200, model returns `"300 x 150"` from the image |
| Data URL: `data:image/png;base64,...` | 200, model describes pixel content |
| Data URL: `data:;base64,...` (no MIME) | 200, also works |
| `detail: auto` / `low` / `high` | All accepted |

### Verified broken

| Source | Result |
|---|---|
| `upload.wikimedia.org/...` (any URL) | **500 Internal Server Error** consistently |
| `https://example.com/does-not-exist.png` (404 URL) | 500 |
| `data:image/png;base64,!!!notbase64!!!` (invalid base64) | 500 |

The pattern: the gateway will return 500 when it can't fetch/decode the URL. Wikipedia is consistently blocked — probably a user-agent or referrer check on Wikimedia's side, or a fetch-policy on the gateway.

### Recommended pattern: data URLs

The most reliable way to send images is **base64-inlined as a data URL** — it doesn't depend on the gateway fetching anything:

```python
import base64
from openai import OpenAI

with open("photo.png", "rb") as f:
    data = base64.b64encode(f.read()).decode()

resp = client.chat.completions.create(
    model="subconscious/tim-qwen3.6-27b",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "What's in this image?"},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{data}"}},
        ],
    }],
    max_tokens=200,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
print(resp.choices[0].message.content)
```

### Don't rely on this for production vision use cases

Despite working in practice, vision is **not in the model's official spec**. Treat it as undocumented behavior that could change. If you need a vision model, pick a different provider.

If you're going to use it:
- Prefer data URLs over public URLs for reliability
- Test every URL source before depending on it
- Handle 500s gracefully (retry once, fall back to text-only)
- Compress images aggressively — large base64 payloads bloat request size

## Audio input — NOT supported

`input_audio` content blocks return **400** for every format we tested (wav, mp3, ogg, flac):

```
23 validation errors:
  {'type': 'value_error', 'loc': ('body', 'messages', 0, ...), ...}
```

sglang's validator rejects the `input_audio` block type before the model sees it. There is no way to send audio to this model.

If you need audio: transcribe externally (Whisper, Deepgram) and send the text.

## File input — NOT supported

`file` content blocks return **400** for all variants:
- `file_data` (base64-encoded text/PDF) — 400
- `file_id` (reference to uploaded file) — 400
- PDF / text / any MIME — 400

The endpoint doesn't accept files. If you have a PDF or document:
- Extract text yourself (PyMuPDF, pdfplumber, unstructured.io) and send as text
- For images of pages, use the `image_url` data-URL pattern above

## Video — NOT supported

| Block type | Result |
|---|---|
| `{type: "video", ...}` | 400 |
| `{type: "video_url", ...}` | 500 |

No video at all. Extract keyframes as images if needed, or use a different model.

## Cost considerations

When vision does work, the image is sent as part of the prompt — base64-inlined images count toward `prompt_tokens`. A 200KB image base64-encoded is ~265 KB on the wire and consumes thousands of input tokens. Be deliberate about size — compress to WebP / JPEG before encoding.

## Summary table

| Modality | Block type | Status |
|---|---|---|
| Text | `text` | ✓ Standard |
| Vision (URL) | `image_url` (URL) | ⚠ Works on most URLs; Wikipedia consistently 500s |
| Vision (data URL) | `image_url` (`data:...`) | ✓ Most reliable path; not officially documented |
| Audio | `input_audio` | ✗ 400 for all formats |
| File | `file` | ✗ 400 (file_data, file_id, any MIME) |
| Video | `video` / `video_url` | ✗ 400 / 500 |

The skill's overall posture: **build text-only by default**. If you need a single image input, the data-URL path works but is not officially supported.
