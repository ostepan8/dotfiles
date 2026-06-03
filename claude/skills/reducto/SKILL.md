---
name: Reducto
description: >-
  This skill should be used when the user asks to "parse a document with Reducto",
  "extract data from PDF", "use Reducto API", "set up Reducto SDK", "convert document to JSON",
  "extract fields from document", "split a multi-document file", "edit/fill a PDF form",
  "configure Reducto OCR", "use agentic OCR", or mentions Reducto, REDUCTO_API_KEY,
  reducto:// file IDs, or document intelligence pipelines. Provides comprehensive guidance
  for Reducto's document processing API including parse, extract, split, and edit operations.
version: 0.1.0
---

# Reducto: Document Intelligence Platform

Reducto converts complex documents (PDFs, images, spreadsheets, slides) into structured data via a hybrid multi-pass pipeline combining computer vision, vision-language models, and proprietary Agentic OCR.

## Core Architecture

**Hybrid Multi-Pass Pipeline:**

1. **Layout-First Computer Vision** — Segments documents visually, identifying regions (tables, headers, figures, text blocks) with bounding box coordinates
2. **Vision-Language Models (VLMs)** — Interprets regions contextually, linking labels to values, understanding tables, classifying segments
3. **Agentic OCR** — Multi-pass self-correction system that detects and fixes errors (misplaced columns/rows, field mismatches, corrupted table structure). Mimics human review by comparing extracted results to visual layout, cross-referencing fields, and rechecking low-confidence regions

## Four Primary API Endpoints

| Endpoint | Purpose | Key Use Case |
|----------|---------|--------------|
| **Parse** | Convert documents to structured JSON (text, tables, figures, metadata) | Document ingestion, RAG pipelines |
| **Extract** | Schema-driven field extraction using JSON Schema | Structured data capture from varied layouts |
| **Split** | Separate multi-document files into distinct segments | Binders, packets, mixed file types |
| **Edit** | Write data back into documents (fill forms, checkboxes, cells) | PDF/DOCX form filling |

## Authentication

```
Authorization: Bearer <REDUCTO_API_KEY>
```

Obtain API key from the Reducto Studio dashboard. Use environment-specific keys for dev/staging/prod.

## Document Input Methods

1. **Upload** — `POST /upload` returns a `file_id` with `reducto://` prefix
2. **Direct URL** — Pass any accessible URL (presigned S3 URLs work)
3. **Job chaining** — Use `jobid://` prefix to chain operations on previous results

## Quick Start (Python SDK)

```python
from reducto import Reducto
from pathlib import Path
import os

client = Reducto(api_key=os.environ["REDUCTO_API_KEY"])

# Upload a document
upload = client.upload(file=Path("document.pdf"))

# Parse with agentic OCR for handwriting
result = client.parse.run(
    input=upload.file_id,
    enhance={"agentic": ["handwriting"]},
    retrieval={"chunking": {"chunk_mode": "variable"}}
)

# Extract structured fields with a JSON schema
extracted = client.extract.run(
    input=upload.file_id,
    instructions={
        "schema": {
            "type": "object",
            "properties": {
                "invoice_number": {"type": "string"},
                "total": {"type": "number"}
            }
        }
    }
)
```

Async support is available via `AsyncReducto`.

## Response Structure (Parse)

Each parse response contains chunks with typed blocks, bounding boxes, and confidence scores:

```json
{
  "job_id": "string",
  "duration": 1.23,
  "usage": {"num_pages": 5, "credits": 0.75},
  "result": {
    "chunks": [{
      "content": "string",
      "embed": "string",
      "blocks": [{
        "type": "Header|Text|Table|Figure|...",
        "bbox": {"left": 0, "top": 0, "width": 100, "height": 50, "page": 0},
        "content": "string",
        "confidence": "low|medium|high"
      }]
    }]
  }
}
```

## Configuration Quick Reference

**OCR Systems:** `standard` (default), `multilingual`, `agentic` (~2x cost, highest accuracy)

**Chunking Modes:** `disabled`, `variable` (semantic, best for RAG), `page`, `block`, `fixed`

**Extraction Modes:** `hybrid` (default), `vision`, `text`

**Table Formats:** `dynamic`, `markdown`

For full configuration options, consult **`references/api-reference.md`**.

## Error Handling

```python
import reducto

try:
    result = client.parse.run(input=file_url)
except reducto.AuthenticationError:    # 401 - Invalid API key
    pass
except reducto.RateLimitError:         # 429 - Back off and retry
    pass
except reducto.APIConnectionError:     # Network issue
    pass
except reducto.APIStatusError as e:    # Other non-2xx
    print(e.status_code, e.response)
```

## Processing Modes

- **Synchronous** — Response includes full result (or presigned URL if too large)
- **Asynchronous** — Returns `job_id`; poll via `/job` endpoint or configure a webhook

## Agent Integration Pattern

For AI agents consuming Reducto:

1. **Upload → Parse → Extract → Verify** — Always verify citations before committing outputs
2. **Schema-first design** — Define strict JSON schemas per document type; use enums to constrain outputs
3. **Escalation strategy** — Start with standard OCR, escalate to agentic for low-confidence regions
4. **Chunking for RAG** — Use `variable` mode to preserve semantic boundaries (250-1500 chars/chunk)

## Pricing

- Credit-based model; standard tier at $0.015/credit (15k free credits to start)
- Agentic OCR costs ~2x standard
- Simple pages are auto-discounted

## Enterprise & Security

SOC2 Type I/II, HIPAA with BAA, zero data retention (24hr expiry). Deployment options: SaaS, VPC, on-prem/air-gapped. Regional endpoints (EU/AU). No training on customer data.

## Limitations

- Password-protected PDFs not supported
- Large responses return presigned URLs instead of inline data
- Rate limiting applies; implement exponential backoff
- Parse must complete before extract (extraction quality depends on parse quality)
- No real-time streaming of results

## Additional Resources

### Reference Files

For detailed technical documentation, consult:
- **`references/api-reference.md`** — Full API endpoint specs, configuration options, and response schemas
- **`references/sdk-guide.md`** — Complete Python SDK usage, async patterns, and error handling
- **`references/best-practices.md`** — Schema design, prompt design, agent integration patterns, and performance tips

### Example Files

Working code examples in `examples/`:
- **`examples/parse_and_extract.py`** — End-to-end document parsing and field extraction
- **`examples/async_batch.py`** — Async batch processing with error recovery
