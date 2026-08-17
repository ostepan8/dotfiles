"""
Reducto: Async batch processing with error recovery.

Demonstrates:
- Processing multiple documents concurrently
- Two-pass OCR strategy (standard → agentic escalation)
- Error handling with retry logic
- Collecting results with per-document status
"""

import asyncio
import os
import time
from pathlib import Path

from reducto import AsyncReducto
import reducto


async def upload_with_retry(
    client: AsyncReducto, file_path: Path, max_retries: int = 3
):
    """Upload a file with retry on transient failures."""
    for attempt in range(max_retries):
        try:
            return await client.upload(file=file_path)
        except reducto.RateLimitError:
            if attempt == max_retries - 1:
                raise
            wait = 2 ** attempt
            print(f"  Rate limited uploading {file_path.name}, "
                  f"retrying in {wait}s...")
            await asyncio.sleep(wait)
        except reducto.APIConnectionError:
            if attempt == max_retries - 1:
                raise
            await asyncio.sleep(1)


async def parse_with_escalation(
    client: AsyncReducto,
    file_id: str,
    filename: str,
    confidence_threshold: float = 0.7,
):
    """
    Two-pass parse strategy:
    1. Standard OCR (fast, cheap)
    2. Agentic OCR if low-confidence blocks detected
    """
    # First pass: standard OCR
    result = await client.parse.run(
        input=file_id,
        retrieval={"chunking": {"chunk_mode": "variable"}},
        settings={"ocr_system": "standard", "extraction_mode": "hybrid"},
    )

    # Check for low-confidence blocks
    low_confidence_count = sum(
        1
        for chunk in result.result.chunks
        for block in chunk.blocks
        if block.confidence == "low"
    )

    total_blocks = sum(
        len(chunk.blocks) for chunk in result.result.chunks
    )

    if total_blocks > 0 and low_confidence_count / total_blocks > 0.2:
        print(f"  {filename}: {low_confidence_count}/{total_blocks} "
              f"low-confidence blocks, escalating to agentic OCR...")
        result = await client.parse.run(
            input=file_id,
            enhance={"agentic": []},
            retrieval={"chunking": {"chunk_mode": "variable"}},
            settings={"ocr_system": "agentic", "extraction_mode": "hybrid"},
        )

    return result


async def process_document(
    client: AsyncReducto,
    file_path: Path,
    schema: dict,
) -> dict:
    """Process a single document: upload → parse → extract."""
    filename = file_path.name
    try:
        # Upload
        upload = await upload_with_retry(client, file_path)
        print(f"  Uploaded: {filename}")

        # Parse with escalation
        parse_result = await parse_with_escalation(
            client, upload.file_id, filename
        )
        print(f"  Parsed: {filename} "
              f"({parse_result.usage.num_pages} pages, "
              f"{parse_result.usage.credits} credits)")

        # Extract
        extract_result = await client.extract.run(
            input=upload.file_id,
            instructions={"schema": schema},
        )
        print(f"  Extracted: {filename}")

        return {
            "file": filename,
            "status": "success",
            "pages": parse_result.usage.num_pages,
            "credits": parse_result.usage.credits,
            "fields": {
                name: {
                    "value": field.value,
                    "confidence": field.confidence,
                }
                for name, field in extract_result.result.fields.items()
            },
        }

    except reducto.AuthenticationError:
        return {"file": filename, "status": "error", "error": "Invalid API key"}
    except reducto.RateLimitError:
        return {"file": filename, "status": "error", "error": "Rate limited after retries"}
    except reducto.APIStatusError as e:
        return {"file": filename, "status": "error", "error": f"API error {e.status_code}"}
    except Exception as e:
        return {"file": filename, "status": "error", "error": str(e)}


async def batch_process(
    file_paths: list[Path],
    schema: dict,
    concurrency: int = 5,
):
    """
    Process a batch of documents with controlled concurrency.

    Args:
        file_paths: List of document paths to process
        schema: JSON schema for extraction
        concurrency: Max concurrent operations
    """
    client = AsyncReducto(api_key=os.environ["REDUCTO_API_KEY"])
    semaphore = asyncio.Semaphore(concurrency)

    async def limited_process(path):
        async with semaphore:
            return await process_document(client, path, schema)

    start = time.time()
    results = await asyncio.gather(*[
        limited_process(path) for path in file_paths
    ])
    elapsed = time.time() - start

    # Summary
    success = [r for r in results if r["status"] == "success"]
    errors = [r for r in results if r["status"] == "error"]
    total_pages = sum(r.get("pages", 0) for r in success)
    total_credits = sum(r.get("credits", 0) for r in success)

    print(f"\n=== Batch Complete ===")
    print(f"  Documents: {len(success)} success, {len(errors)} failed")
    print(f"  Pages: {total_pages}")
    print(f"  Credits: {total_credits:.2f}")
    print(f"  Time: {elapsed:.1f}s")

    if errors:
        print(f"\n  Failures:")
        for r in errors:
            print(f"    {r['file']}: {r['error']}")

    return results


# Example usage
if __name__ == "__main__":
    invoice_schema = {
        "type": "object",
        "properties": {
            "invoice_number": {"type": "string"},
            "date": {"type": "string"},
            "total": {"type": "number"},
            "vendor": {"type": "string"},
        },
    }

    documents = list(Path("./documents").glob("*.pdf"))
    print(f"Processing {len(documents)} documents...")

    results = asyncio.run(
        batch_process(documents, invoice_schema, concurrency=5)
    )
