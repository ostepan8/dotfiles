# Reducto Best Practices

## Schema Design for Extract

### Field Naming

Match field names to document terminology. Use the same language found on the document to improve extraction accuracy.

```json
{
  "type": "object",
  "properties": {
    "invoice_number": {"type": "string"},
    "po_number": {"type": "string"},
    "bill_to_address": {"type": "string"}
  }
}
```

Avoid abstract or generic names like `field1`, `id`, or `data`.

### Use Enums for Constrained Values

When a field has a limited set of valid values, constrain with enums:

```json
{
  "status": {
    "type": "string",
    "enum": ["active", "inactive", "pending"],
    "description": "Account status as shown in the status field"
  }
}
```

### Add Descriptions

Every field should have a description explaining what it represents and where to find it on the document:

```json
{
  "total_due": {
    "type": "number",
    "description": "The total amount due, typically found in the bottom-right summary section"
  }
}
```

### Keep Nesting Shallow

Limit nesting to 2-3 levels maximum. Deep nesting increases extraction complexity and error rate.

**Good:**
```json
{
  "address": {
    "type": "object",
    "properties": {
      "street": {"type": "string"},
      "city": {"type": "string"},
      "state": {"type": "string"},
      "zip": {"type": "string"}
    }
  }
}
```

**Avoid:**
```json
{
  "contact": {
    "primary": {
      "address": {
        "components": {
          "street": {"type": "string"}
        }
      }
    }
  }
}
```

### Use Arrays for Lists and Tables

Extract repeated structures (line items, table rows) as arrays:

```json
{
  "line_items": {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "description": {"type": "string"},
        "qty": {"type": "number"},
        "price": {"type": "number"}
      }
    }
  }
}
```

### Avoid Derived Fields

Do not include fields that can be calculated from other extracted data. Calculate totals, percentages, and derived values downstream rather than asking Reducto to extract them.

---

## Prompt Design

### Provide Document Context

```python
instructions={
    "schema": schema,
    "prompt": "This is a healthcare insurance claim form (CMS-1500). "
              "Patient info is in the top section, "
              "provider info in the bottom section."
}
```

### Specify Edge Case Handling

```python
instructions={
    "schema": schema,
    "prompt": "If a field is empty or illegible, return null. "
              "Dates may appear as MM/DD/YYYY or YYYY-MM-DD."
}
```

### Keep Prompts Concise

Target 1-3 sentences. Over-constraining reduces flexibility and can decrease accuracy on edge cases.

### Avoid Over-Constraining

Let the schema define structure; let the prompt provide context. Do not repeat schema definitions in the prompt.

---

## Agent Integration Patterns

### Standard Document Processing Pipeline

```
upload → parse (with layout/bboxes) → extract (with schema) → verify citations
```

Always follow this flow. Parse quality directly affects extraction accuracy.

### Citation Verification

Enable bounding boxes for all extractions and implement a verification step:

```python
extracted = client.extract.run(input=file_id, instructions={"schema": schema})

for field_name, field_data in extracted.result.fields.items():
    if field_data.confidence < 0.8:
        print(f"LOW CONFIDENCE: {field_name} = {field_data.value} "
              f"(conf: {field_data.confidence})")
        print(f"  Citation: {field_data.citation.text}")
        print(f"  Location: page {field_data.citation.bbox.page}")
```

### Schema-First Design

Define strict JSON schemas for each document type the agent will process. Use enums to constrain outputs. Request field-level confidence scores to drive decision-making.

### Error Recovery Strategy

1. Start with standard OCR for cost efficiency
2. Check confidence scores on results
3. Escalate to agentic OCR for low-confidence fields or complex documents
4. Implement retry logic with exponential backoff for transient failures
5. Handle partial results gracefully — extract what is available

```python
# Two-pass strategy
result = client.parse.run(
    input=file_id,
    settings={"ocr_system": "standard"}
)

low_confidence_blocks = [
    b for chunk in result.result.chunks
    for b in chunk.blocks
    if b.confidence == "low"
]

if low_confidence_blocks:
    # Re-process with agentic OCR
    result = client.parse.run(
        input=file_id,
        enhance={"agentic": []},
        settings={"ocr_system": "agentic"}
    )
```

### Chunking Strategy for RAG

- Use `variable` mode for semantic chunking (best for retrieval)
- Preserve layout metadata and reading order
- Default chunk size: 250-1500 characters
- Include bounding boxes for source attribution

```python
result = client.parse.run(
    input=file_id,
    retrieval={
        "chunking": {"chunk_mode": "variable"},
        "embedding_optimized": True
    }
)

# Store chunks with metadata in vector DB
for chunk in result.result.chunks:
    store_in_vector_db(
        text=chunk.embed,
        metadata={
            "content": chunk.content,
            "blocks": [
                {"type": b.type, "bbox": b.bbox, "confidence": b.confidence}
                for b in chunk.blocks
            ]
        }
    )
```

---

## Performance Optimization

### Choose the Right OCR System

| Scenario | OCR System | Cost |
|----------|-----------|------|
| Standard text documents | `standard` | 1x |
| Non-Latin scripts | `multilingual` | ~1.5x |
| Handwriting, complex layouts | `agentic` | ~2x |
| Mixed content | Start `standard`, escalate as needed | Variable |

### Choose the Right Extraction Mode

| Document Type | Mode | Rationale |
|--------------|------|-----------|
| Text-heavy (contracts, articles) | `text` | Faster, sufficient |
| Visual-heavy (forms, diagrams) | `vision` | Better layout understanding |
| Mixed (invoices, reports) | `hybrid` | Best overall (default) |

### Batch Processing

Process multiple documents concurrently using async:

```python
async def process_batch(file_paths):
    client = AsyncReducto()
    tasks = []
    for path in file_paths:
        upload = await client.upload(file=path)
        tasks.append(client.parse.run(input=upload.file_id))
    return await asyncio.gather(*tasks, return_exceptions=True)
```

---

## Security & Compliance

### Data Handling

- Zero data retention: documents expire after 24 hours
- No training on customer data
- SOC2 Type I/II certified
- HIPAA compliant with BAA available

### API Key Management

- Use environment-specific keys (dev/staging/prod)
- Never commit API keys to version control
- Rotate keys periodically
- Use least-privilege access where possible

### Deployment Options

| Option | Use Case |
|--------|----------|
| SaaS | Default, fastest setup |
| VPC | Data residency requirements |
| On-prem / Air-gapped | Highest security, regulated industries |
| Regional endpoints (EU/AU) | GDPR/data sovereignty |

---

## Production Performance Benchmarks

- 250M+ pages processed in production
- 99.9%+ uptime SLA
- Outperforms AWS/Google/Azure by ~20% on RD-TableBench
- Case studies: 16x faster audits, <1min SLAs, 95%+ throughput
- Customers: Scale AI, Vanta, Airtable, Fortune 10 enterprises

---

## Common Pitfalls

### 1. Skipping Parse Before Extract

Extract quality depends on parse quality. Always parse first, especially for complex documents.

### 2. Over-Complex Schemas

Keep schemas focused on what is actually needed. Large schemas with many optional fields increase processing time and reduce per-field accuracy.

### 3. Ignoring Confidence Scores

Always check confidence scores. Low-confidence extractions should trigger review or re-processing with agentic OCR.

### 4. Not Using Job Chaining

When running parse then extract on the same document, use `jobid://` to avoid re-uploading and re-processing.

### 5. Synchronous Processing for Large Batches

Use async processing for batches larger than 5-10 documents. Synchronous calls block and waste time on large workloads.

### 6. Hardcoding Bounding Boxes

Bounding box coordinates vary between documents. Use extract's schema-based approach rather than hardcoding coordinates unless editing a known template.
