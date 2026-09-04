# Reducto Python SDK Guide

## Installation

```bash
pip install reducto
```

## Client Initialization

### Synchronous Client

```python
from reducto import Reducto
import os

# Explicit API key
client = Reducto(api_key="your-api-key")

# From environment (recommended)
client = Reducto(api_key=os.environ["REDUCTO_API_KEY"])

# Auto-detect from REDUCTO_API_KEY env var
client = Reducto()
```

### Async Client

```python
from reducto import AsyncReducto

client = AsyncReducto(api_key=os.environ["REDUCTO_API_KEY"])
```

---

## Document Upload

```python
from pathlib import Path

# Upload from local file
upload = client.upload(file=Path("document.pdf"))
print(upload.file_id)  # "reducto://abc123..."

# Use direct URL instead of uploading
file_url = "https://example.com/document.pdf"
```

Both `file_id` and direct URLs are accepted as `input` in all endpoints.

---

## Parse Operations

### Basic Parse

```python
result = client.parse.run(input=upload.file_id)

for chunk in result.result.chunks:
    print(chunk.content)
    for block in chunk.blocks:
        print(f"  [{block.type}] {block.content[:80]}...")
        print(f"  Confidence: {block.confidence}")
        print(f"  BBox: page={block.bbox.page}, "
              f"({block.bbox.left},{block.bbox.top}) "
              f"{block.bbox.width}x{block.bbox.height}")
```

### Parse with Agentic OCR

```python
result = client.parse.run(
    input=upload.file_id,
    enhance={"agentic": ["handwriting"]},
    settings={"ocr_system": "agentic"}
)
```

### Parse with Chunking for RAG

```python
result = client.parse.run(
    input=upload.file_id,
    retrieval={
        "chunking": {"chunk_mode": "variable"},
        "embedding_optimized": True
    }
)

# Use embed field for vector store
for chunk in result.result.chunks:
    embedding_text = chunk.embed  # Optimized for embeddings
    content_text = chunk.content  # Full content with formatting
```

### Parse with Table Handling

```python
result = client.parse.run(
    input=upload.file_id,
    formatting={
        "table_output_format": "markdown",
        "merge_tables": True
    }
)
```

### Parse with OCR Data

```python
result = client.parse.run(
    input=upload.file_id,
    settings={
        "return_ocr_data": True,
        "return_images": ["Figure", "Table"]
    }
)

# Access raw OCR data
for word in result.result.ocr.words:
    print(word)
```

---

## Extract Operations

### Basic Extraction

```python
extracted = client.extract.run(
    input=upload.file_id,
    instructions={
        "schema": {
            "type": "object",
            "properties": {
                "invoice_number": {"type": "string", "description": "Invoice ID"},
                "date": {"type": "string", "description": "Invoice date"},
                "total": {"type": "number", "description": "Total amount due"},
                "vendor": {"type": "string", "description": "Vendor/seller name"}
            }
        }
    }
)

for field_name, field_data in extracted.result.fields.items():
    print(f"{field_name}: {field_data.value} "
          f"(confidence: {field_data.confidence})")
```

### Extraction with Arrays (Line Items)

```python
extracted = client.extract.run(
    input=upload.file_id,
    instructions={
        "schema": {
            "type": "object",
            "properties": {
                "line_items": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "description": {"type": "string"},
                            "quantity": {"type": "number"},
                            "unit_price": {"type": "number"},
                            "total": {"type": "number"}
                        }
                    }
                }
            }
        }
    }
)
```

### Extraction with Enums

```python
extracted = client.extract.run(
    input=upload.file_id,
    instructions={
        "schema": {
            "type": "object",
            "properties": {
                "document_type": {
                    "type": "string",
                    "enum": ["invoice", "receipt", "purchase_order", "credit_note"],
                    "description": "The type of financial document"
                },
                "currency": {
                    "type": "string",
                    "enum": ["USD", "EUR", "GBP", "CAD"],
                    "description": "Currency of the transaction"
                }
            }
        }
    }
)
```

### Extraction with Prompt Context

```python
extracted = client.extract.run(
    input=upload.file_id,
    instructions={
        "schema": {
            "type": "object",
            "properties": {
                "patient_name": {"type": "string"},
                "diagnosis_code": {"type": "string"},
                "prescribed_medications": {
                    "type": "array",
                    "items": {"type": "string"}
                }
            }
        },
        "prompt": "This is a medical intake form. Extract patient information "
                  "from the top section and diagnosis from the physician notes."
    }
)
```

---

## Split Operations

```python
split_result = client.split.run(
    input=upload.file_id,
    split_description="Separate each invoice in this binder into individual documents"
)

for segment in split_result.result.segments:
    print(f"Pages {segment.start_page}-{segment.end_page}: {segment.label}")
```

---

## Edit Operations

```python
edit_result = client.edit.run(
    input=upload.file_id,
    edits=[
        {
            "field": "applicant_name",
            "value": "John Doe",
            "bbox": {"left": 100, "top": 200, "width": 300, "height": 20, "page": 0}
        },
        {
            "field": "date",
            "value": "2025-01-15",
            "bbox": {"left": 100, "top": 250, "width": 200, "height": 20, "page": 0}
        }
    ],
    policy="best_effort"
)
```

---

## Async Operations

### Using AsyncReducto

```python
import asyncio
from reducto import AsyncReducto

async def process_documents():
    client = AsyncReducto(api_key=os.environ["REDUCTO_API_KEY"])

    upload = await client.upload(file=Path("document.pdf"))
    result = await client.parse.run(input=upload.file_id)

    for chunk in result.result.chunks:
        print(chunk.content)

asyncio.run(process_documents())
```

### Batch Processing with Async

```python
async def batch_process(file_paths: list[Path]):
    client = AsyncReducto()

    # Upload all files concurrently
    uploads = await asyncio.gather(*[
        client.upload(file=path) for path in file_paths
    ])

    # Parse all files concurrently
    results = await asyncio.gather(*[
        client.parse.run(input=upload.file_id)
        for upload in uploads
    ], return_exceptions=True)

    for path, result in zip(file_paths, results):
        if isinstance(result, Exception):
            print(f"Failed: {path} - {result}")
        else:
            print(f"Success: {path} - {result.usage.num_pages} pages")

    return results
```

---

## Job Chaining

Chain operations using `jobid://` prefix:

```python
# Parse first
parse_result = client.parse.run(input=upload.file_id)

# Extract using parse job output
extracted = client.extract.run(
    input=f"jobid://{parse_result.job_id}",
    instructions={"schema": {...}}
)
```

---

## Error Handling

### Exception Types

```python
import reducto

try:
    result = client.parse.run(input=file_url)
except reducto.AuthenticationError:
    # 401 - Invalid or expired API key
    print("Check REDUCTO_API_KEY")
except reducto.RateLimitError:
    # 429 - Rate limit exceeded
    print("Back off and retry")
except reducto.APIConnectionError as e:
    # Network connectivity issue
    print(f"Connection failed: {e.__cause__}")
except reducto.APIStatusError as e:
    # Other non-2xx response
    print(f"Status {e.status_code}: {e.response}")
```

### Retry Pattern with Exponential Backoff

```python
import time
import reducto

def parse_with_retry(client, input_ref, max_retries=5):
    for attempt in range(max_retries):
        try:
            return client.parse.run(input=input_ref)
        except reducto.RateLimitError:
            if attempt == max_retries - 1:
                raise
            wait = 2 ** attempt
            print(f"Rate limited, retrying in {wait}s...")
            time.sleep(wait)
        except reducto.APIConnectionError:
            if attempt == max_retries - 1:
                raise
            time.sleep(1)
```

---

## Environment Configuration

### Recommended Setup

```bash
# .env
REDUCTO_API_KEY=your-api-key-here

# Development
REDUCTO_API_KEY_DEV=dev-key
# Staging
REDUCTO_API_KEY_STAGING=staging-key
# Production
REDUCTO_API_KEY_PROD=prod-key
```

```python
import os

env = os.environ.get("ENVIRONMENT", "dev")
api_key = os.environ[f"REDUCTO_API_KEY_{env.upper()}"]
client = Reducto(api_key=api_key)
```
