# Reducto API Reference

## Base URL

All API requests use the Reducto API base URL with Bearer token authentication:

```
Authorization: Bearer <REDUCTO_API_KEY>
```

---

## Upload Endpoint

Upload a document to receive a `file_id` for use in subsequent operations.

**Request:** `POST /upload`
- Accepts multipart file upload
- Returns `file_id` with `reducto://` prefix

**Usage:**
```python
upload = client.upload(file=Path("document.pdf"))
# upload.file_id => "reducto://abc123..."
```

Supported formats: PDF, PNG, JPG, TIFF, XLSX, PPTX, DOCX.

---

## Parse Endpoint

Convert documents to structured JSON with text, tables, figures, and metadata.

**Request:** `POST /parse`

**Input:**
- `file_id` (reducto:// prefix) from upload
- Direct URL (presigned S3 URLs work)
- `jobid://` prefix for chaining

### Response Schema

```json
{
  "job_id": "string",
  "duration": 1.23,
  "usage": {
    "num_pages": 5,
    "credits": 0.75
  },
  "result": {
    "chunks": [
      {
        "content": "string",
        "embed": "string",
        "blocks": [
          {
            "type": "Header|Text|Table|Figure|ListItem|PageBreak|Caption|Footnote",
            "bbox": {
              "left": 0,
              "top": 0,
              "width": 100,
              "height": 50,
              "page": 0
            },
            "content": "string",
            "confidence": "low|medium|high",
            "granular_confidence": {
              "extract_confidence": 0.95,
              "parse_confidence": 0.92
            }
          }
        ]
      }
    ],
    "ocr": {
      "words": [],
      "lines": []
    }
  }
}
```

### Block Types

| Type | Description |
|------|-------------|
| `Header` | Section headings and titles |
| `Text` | Body text paragraphs |
| `Table` | Tabular data (markdown or structured) |
| `Figure` | Images, charts, diagrams |
| `ListItem` | Bulleted or numbered list items |
| `PageBreak` | Page boundary markers |
| `Caption` | Figure/table captions |
| `Footnote` | Footer notes and references |

### Full Configuration Options

```json
{
  "enhance": {
    "agentic": [],
    "summarize_figures": false
  },
  "retrieval": {
    "chunking": {
      "chunk_mode": "disabled|variable|page|block|fixed"
    },
    "embedding_optimized": false
  },
  "formatting": {
    "table_output_format": "dynamic|markdown",
    "merge_tables": false
  },
  "settings": {
    "ocr_system": "standard|multilingual|agentic",
    "extraction_mode": "hybrid|vision|text",
    "return_ocr_data": false,
    "return_images": []
  }
}
```

### Configuration Details

#### `enhance`

- **`agentic`** (array): Enable agentic OCR for specific scenarios. Pass scenario identifiers (e.g., `["handwriting"]`). Increases accuracy but costs ~2x standard.
- **`summarize_figures`** (bool): Generate text summaries for figures/charts.

#### `retrieval`

- **`chunking.chunk_mode`**:
  - `disabled` — No chunking, return raw blocks
  - `variable` — Semantic boundaries, best for RAG (250-1500 chars/chunk)
  - `page` — One chunk per page
  - `block` — One chunk per block
  - `fixed` — Fixed character count chunks
- **`embedding_optimized`** (bool): Optimize `embed` field for vector embeddings.

#### `formatting`

- **`table_output_format`**: `dynamic` (auto-selects best format) or `markdown`.
- **`merge_tables`** (bool): Merge tables split across pages.

#### `settings`

- **`ocr_system`**:
  - `standard` — Default, fast, cost-effective
  - `multilingual` — Enhanced for non-Latin scripts
  - `agentic` — Multi-pass self-correction, highest accuracy (~2x cost)
- **`extraction_mode`**:
  - `hybrid` — Combines vision + text (default, recommended)
  - `vision` — Vision-only, better for heavily visual documents
  - `text` — Text-only, faster for text-heavy documents
- **`return_ocr_data`** (bool): Include raw OCR word/line data in response.
- **`return_images`** (array): Return base64 images for specified block types.

---

## Extract Endpoint

Schema-driven field extraction using JSON Schema definitions.

**Request:** `POST /extract`

### Input Schema Definition

```json
{
  "input": "reducto://file_id",
  "instructions": {
    "schema": {
      "type": "object",
      "properties": {
        "field_name": {
          "type": "string|number|boolean|array|object",
          "description": "What this field represents",
          "enum": ["value1", "value2"]
        }
      }
    },
    "prompt": "Optional context about the document type"
  }
}
```

### Extract Response

```json
{
  "job_id": "string",
  "result": {
    "fields": {
      "field_name": {
        "value": "extracted_value",
        "confidence": 0.95,
        "citation": {
          "bbox": {"left": 0, "top": 0, "width": 100, "height": 20, "page": 0},
          "text": "source text from document"
        }
      }
    }
  }
}
```

Each extracted field includes:
- **`value`** — The extracted data
- **`confidence`** — Float score (0-1)
- **`citation`** — Bounding box and source text for provenance

### Supported Field Types

| JSON Schema Type | Use Case |
|------------------|----------|
| `string` | Names, IDs, addresses |
| `number` | Amounts, quantities, percentages |
| `boolean` | Checkboxes, yes/no fields |
| `array` | Line items, lists, repeated structures |
| `object` | Nested structures (e.g., address with street/city/zip) |

---

## Split Endpoint

Separate multi-document files or long forms into distinct logical segments.

**Request:** `POST /split`

```json
{
  "input": "reducto://file_id",
  "split_description": "Description of how to split the document"
}
```

### Response

Returns an array of segments with page ranges and metadata:

```json
{
  "result": {
    "segments": [
      {
        "start_page": 0,
        "end_page": 3,
        "label": "Invoice #12345",
        "confidence": 0.92
      }
    ]
  }
}
```

Features:
- Maintains reading order and semantic boundaries
- Handles binders, packets, mixed file types
- Useful for pre-processing before parse/extract

---

## Edit Endpoint

Write data back into documents — fill form fields, checkboxes, and table cells.

**Request:** `POST /edit`

```json
{
  "input": "reducto://file_id",
  "edits": [
    {
      "field": "field_name",
      "value": "new_value",
      "bbox": {"left": 0, "top": 0, "width": 100, "height": 20, "page": 0}
    }
  ],
  "policy": "strict|best_effort"
}
```

### Policies

- **`strict`** — Fail if any edit cannot be applied precisely
- **`best_effort`** — Apply as many edits as possible, report failures

Supported formats: PDF, DOCX.

---

## Job Status Endpoint

Poll for async job completion.

**Request:** `GET /job/{job_id}`

```json
{
  "status": "pending|processing|completed|failed",
  "result": { ... },
  "error": "string (if failed)"
}
```

---

## Pricing & Credits

| Factor | Impact |
|--------|--------|
| Standard tier | $0.015/credit after 15k free |
| Simple pages | Auto-discounted |
| Agentic OCR | ~2x standard cost |
| Page count | Linear scaling |
| Operation type | Parse/extract/split/edit each consume credits |

Credit consumption varies by document complexity. Simple text-heavy pages cost less than complex multi-table layouts.

---

## Rate Limiting

Rate limits apply per API key. Implement exponential backoff on 429 responses:

```python
import time

def call_with_retry(fn, max_retries=5):
    for attempt in range(max_retries):
        try:
            return fn()
        except reducto.RateLimitError:
            wait = 2 ** attempt
            time.sleep(wait)
    raise Exception("Max retries exceeded")
```

---

## HTTP Response Size Limits

Large documents may exceed HTTP response size limits. When this occurs, the response includes a presigned URL to download the full result:

```json
{
  "result_url": "https://...",
  "result": null
}
```

Fetch the URL to retrieve the complete result payload.
