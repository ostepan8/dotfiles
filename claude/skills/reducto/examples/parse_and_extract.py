"""
Reducto: End-to-end document parsing and field extraction.

Demonstrates:
- Uploading a document
- Parsing with variable chunking and agentic OCR
- Extracting structured fields with a JSON schema
- Verifying extraction confidence and citations
"""

import os
from pathlib import Path
from reducto import Reducto

# Initialize client
client = Reducto(api_key=os.environ["REDUCTO_API_KEY"])

# Upload document
upload = client.upload(file=Path("invoice.pdf"))
print(f"Uploaded: {upload.file_id}")

# Parse with variable chunking (best for RAG)
parse_result = client.parse.run(
    input=upload.file_id,
    enhance={"agentic": ["handwriting"]},
    retrieval={
        "chunking": {"chunk_mode": "variable"},
        "embedding_optimized": True,
    },
    formatting={
        "table_output_format": "markdown",
        "merge_tables": True,
    },
    settings={
        "ocr_system": "agentic",
        "extraction_mode": "hybrid",
    },
)

print(f"Parsed {parse_result.usage.num_pages} pages "
      f"({parse_result.usage.credits} credits, {parse_result.duration:.2f}s)")
print(f"Chunks: {len(parse_result.result.chunks)}")

for i, chunk in enumerate(parse_result.result.chunks):
    print(f"\n--- Chunk {i} ---")
    print(chunk.content[:200])
    for block in chunk.blocks:
        print(f"  [{block.type}] confidence={block.confidence} "
              f"page={block.bbox.page}")

# Extract structured fields using JSON schema
invoice_schema = {
    "type": "object",
    "properties": {
        "invoice_number": {
            "type": "string",
            "description": "The invoice number or ID",
        },
        "invoice_date": {
            "type": "string",
            "description": "Date the invoice was issued",
        },
        "vendor_name": {
            "type": "string",
            "description": "Name of the vendor or seller",
        },
        "total_amount": {
            "type": "number",
            "description": "Total amount due on the invoice",
        },
        "currency": {
            "type": "string",
            "enum": ["USD", "EUR", "GBP", "CAD"],
            "description": "Currency of the transaction",
        },
        "line_items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "description": {"type": "string"},
                    "quantity": {"type": "number"},
                    "unit_price": {"type": "number"},
                    "total": {"type": "number"},
                },
            },
            "description": "Individual line items on the invoice",
        },
    },
}

extract_result = client.extract.run(
    input=upload.file_id,
    instructions={
        "schema": invoice_schema,
        "prompt": "This is a vendor invoice. Extract all billing details "
                  "and line items. If a field is not present, return null.",
    },
)

print("\n=== Extracted Fields ===")
for field_name, field_data in extract_result.result.fields.items():
    confidence = field_data.confidence
    status = "OK" if confidence >= 0.8 else "LOW CONFIDENCE"
    print(f"  {field_name}: {field_data.value} "
          f"(confidence: {confidence:.2f}) [{status}]")

    if confidence < 0.8 and field_data.citation:
        print(f"    Citation: \"{field_data.citation.text}\"")
        print(f"    Location: page {field_data.citation.bbox.page}")
