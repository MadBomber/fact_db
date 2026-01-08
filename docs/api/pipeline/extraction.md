# ExtractionPipeline

Concurrent fact extraction from multiple content items.

## Class: `FactDb::Pipeline::ExtractionPipeline`

```ruby
pipeline = FactDb::Pipeline::ExtractionPipeline.new(config)
```

## Methods

### process

```ruby
def process(contents, extractor: config.default_extractor)
```

Process content items sequentially.

**Parameters:**

- `contents` (Array<Content>) - Content records
- `extractor` (Symbol) - Extraction method

**Returns:** `Array<Hash>`

**Example:**

```ruby
contents = Models::Content.where(id: [1, 2, 3])
results = pipeline.process(contents, extractor: :llm)
```

---

### process_parallel

```ruby
def process_parallel(contents, extractor: config.default_extractor)
```

Process content items concurrently.

**Parameters:**

- `contents` (Array<Content>) - Content records
- `extractor` (Symbol) - Extraction method

**Returns:** `Array<Hash>`

**Example:**

```ruby
results = pipeline.process_parallel(contents, extractor: :llm)

results.each do |result|
  puts "Content #{result[:content_id]}:"
  puts "  Facts: #{result[:facts].count}"
  puts "  Error: #{result[:error]}" if result[:error]
end
```

## Pipeline Steps

### Sequential Pipeline

```mermaid
graph LR
    A[Content] --> B[Validate]
    B --> C[Extract]
    C --> D[Validate Facts]
    D --> E[Results]

    style A fill:#1E40AF,stroke:#1E3A8A,color:#FFFFFF
    style B fill:#B45309,stroke:#92400E,color:#FFFFFF
    style C fill:#047857,stroke:#065F46,color:#FFFFFF
    style D fill:#B45309,stroke:#92400E,color:#FFFFFF
    style E fill:#B91C1C,stroke:#991B1B,color:#FFFFFF
```

1. **Validate** - Check content is not empty
2. **Extract** - Run extractor
3. **Validate Facts** - Filter valid facts
4. **Results** - Return extracted facts

### Parallel Pipeline

```mermaid
graph TB
    subgraph Parallel
        A1[Content 1] --> E1[Extract 1]
        A2[Content 2] --> E2[Extract 2]
        A3[Content 3] --> E3[Extract 3]
    end
    E1 --> Aggregate
    E2 --> Aggregate
    E3 --> Aggregate

    style A1 fill:#1E40AF,stroke:#1E3A8A,color:#FFFFFF
    style A2 fill:#1E40AF,stroke:#1E3A8A,color:#FFFFFF
    style A3 fill:#1E40AF,stroke:#1E3A8A,color:#FFFFFF
    style E1 fill:#047857,stroke:#065F46,color:#FFFFFF
    style E2 fill:#047857,stroke:#065F46,color:#FFFFFF
    style E3 fill:#047857,stroke:#065F46,color:#FFFFFF
    style Aggregate fill:#B91C1C,stroke:#991B1B,color:#FFFFFF
```

## Result Structure

```ruby
{
  content_id: 123,
  facts: [<Fact>, <Fact>, ...],  # Extracted facts
  error: nil                      # Error message if failed
}
```

## Usage via Facts

```ruby
facts = FactDb.new

# Sequential
results = facts.batch_extract(content_ids, parallel: false)

# Parallel (default)
results = facts.batch_extract(content_ids, parallel: true)
```

## Error Handling

The pipeline catches errors per-item:

```ruby
results = pipeline.process_parallel(contents)

results.each do |result|
  if result[:error]
    logger.error "Content #{result[:content_id]}: #{result[:error]}"
  else
    logger.info "Content #{result[:content_id]}: #{result[:facts].count} facts"
  end
end
```

## Performance

### Batch Size

Optimal batch size depends on:

- Extractor type (LLM has rate limits)
- Content length
- System resources

```ruby
# Process in optimal batches
contents.each_slice(25) do |batch|
  results = pipeline.process_parallel(batch)
  process_results(results)
end
```

### Memory

For large batches, process and discard:

```ruby
contents.each_slice(50) do |batch|
  results = pipeline.process_parallel(batch)
  save_facts(results.flat_map { |r| r[:facts] })
  # Results discarded after each batch
end
```
