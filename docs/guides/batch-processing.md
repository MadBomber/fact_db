# Batch Processing

FactDb uses the `simple_flow` gem to provide concurrent pipeline processing for efficient batch operations.

## Overview

Batch processing is useful for:

- Processing multiple documents at once
- Resolving many entity names
- Detecting conflicts across entities
- Bulk fact extraction

## Batch Extraction

### Sequential Processing

Process content one at a time:

```ruby
facts = FactDb.new

source_ids = [content1.id, content2.id, content3.id]

results = facts.batch_extract(
  source_ids,
  extractor: :llm,
  parallel: false
)
```

### Parallel Processing

Process content concurrently (default):

```ruby
results = facts.batch_extract(
  source_ids,
  extractor: :llm,
  parallel: true  # default
)

results.each do |result|
  puts "Content #{result[:source_id]}:"
  puts "  Facts extracted: #{result[:facts].count}"
  puts "  Error: #{result[:error]}" if result[:error]
end
```

### Result Structure

```ruby
result = {
  source_id: 123,
  facts: [<Fact>, <Fact>, ...],  # Extracted facts
  error: nil                      # Error message if failed
}
```

## Batch Entity Resolution

Resolve multiple names at once:

```ruby
names = [
  "Paula Chen",
  "John Smith",
  "Microsoft",
  "Acme Corporation",
  "Seattle"
]

results = facts.batch_resolve_entities(names, type: nil)

results.each do |result|
  case result[:status]
  when :resolved
    puts "#{result[:name]} -> #{result[:entity].name}"
  when :not_found
    puts "#{result[:name]} -> Not found"
  when :error
    puts "#{result[:name]} -> Error: #{result[:error]}"
  end
end
```

### With Type Filtering

```ruby
# Only resolve as person entities
results = facts.batch_resolve_entities(names, type: :person)
```

## Conflict Detection

Check multiple entities for conflicting facts:

```ruby
entity_ids = [paula.id, john.id, microsoft.id]

results = facts.detect_fact_conflicts(entity_ids)

results.each do |result|
  if result[:conflict_count] > 0
    puts "Entity #{result[:entity_id]} has #{result[:conflict_count]} conflicts:"
    result[:conflicts].each do |conflict|
      puts "  #{conflict[:fact1].text}"
      puts "  vs"
      puts "  #{conflict[:fact2].text}"
      puts "  Similarity: #{conflict[:similarity]}"
    end
  end
end
```

## Using Pipelines Directly

For more control, use the pipeline classes directly:

### Extraction Pipeline

```ruby
pipeline = FactDb::Pipeline::ExtractionPipeline.new(FactDb.config)

# Sequential
results = pipeline.process(contents, extractor: :llm)

# Parallel
results = pipeline.process_parallel(contents, extractor: :llm)
```

### Resolution Pipeline

```ruby
pipeline = FactDb::Pipeline::ResolutionPipeline.new(FactDb.config)

# Resolve entities
results = pipeline.resolve_entities(names, type: :person)

# Detect conflicts
results = pipeline.detect_conflicts(entity_ids)
```

## SimpleFlow Integration

FactDb's pipelines are built on SimpleFlow:

```ruby
require 'simple_flow'

# Create custom pipeline
pipeline = SimpleFlow::Pipeline.new do
  # Step 1: Validate
  step ->(result) {
    content = result.value
    if source.content.blank?
      result.halt("Empty content")
    else
      result.continue(content)
    end
  }

  # Step 2: Extract
  step ->(result) {
    facts = extractor.extract(result.value)
    result.continue(facts)
  }

  # Step 3: Validate facts
  step ->(result) {
    valid_facts = result.value.select(&:valid?)
    result.continue(valid_facts)
  }
end

# Execute
result = pipeline.call(SimpleFlow::Result.new(content))
```

## Error Handling

### Graceful Degradation

```ruby
results = facts.batch_extract(source_ids, extractor: :llm)

successful = results.select { |r| r[:error].nil? }
failed = results.reject { |r| r[:error].nil? }

puts "Successful: #{successful.count}"
puts "Failed: #{failed.count}"

# Retry failed items with different extractor
if failed.any?
  retry_ids = failed.map { |r| r[:source_id] }
  retry_results = facts.batch_extract(retry_ids, extractor: :rule_based)
end
```

### Logging Errors

```ruby
results.each do |result|
  if result[:error]
    logger.error(
      "Extraction failed",
      source_id: result[:source_id],
      error: result[:error]
    )
  end
end
```

## Performance Considerations

### Optimal Batch Size

```ruby
# Process in batches of 10-50 for optimal performance
source_ids.each_slice(25) do |batch|
  results = facts.batch_extract(batch, parallel: true)
  process_results(results)
end
```

### Rate Limiting

For LLM extraction, add delays between batches:

```ruby
source_ids.each_slice(10) do |batch|
  results = facts.batch_extract(batch, extractor: :llm)
  process_results(results)
  sleep(2)  # Rate limit
end
```

### Memory Management

```ruby
# Process results immediately to avoid memory buildup
source_ids.each_slice(50) do |batch|
  results = facts.batch_extract(batch)

  results.each do |result|
    # Process and discard
    save_facts(result[:facts])
  end

  # Force garbage collection if needed
  GC.start if batch_count % 10 == 0
end
```

## Monitoring

Track batch processing metrics:

```ruby
start_time = Time.now

results = facts.batch_extract(source_ids, parallel: true)

duration = Time.now - start_time
success_rate = results.count { |r| r[:error].nil? }.to_f / results.count

puts "Processed #{results.count} items in #{duration}s"
puts "Success rate: #{(success_rate * 100).round(1)}%"
puts "Items/second: #{(results.count / duration).round(2)}"
```

## Best Practices

### 1. Use Parallel for Large Batches

```ruby
# Sequential for small batches (< 5 items)
if source_ids.count < 5
  results = facts.batch_extract(source_ids, parallel: false)
else
  results = facts.batch_extract(source_ids, parallel: true)
end
```

### 2. Handle Partial Failures

```ruby
def process_batch(source_ids)
  results = facts.batch_extract(source_ids)

  {
    successful: results.select { |r| r[:error].nil? },
    failed: results.reject { |r| r[:error].nil? }
  }
end

batch_result = process_batch(source_ids)
retry_failed(batch_result[:failed]) if batch_result[:failed].any?
```

### 3. Log Progress

```ruby
total = source_ids.count
processed = 0

source_ids.each_slice(25) do |batch|
  results = facts.batch_extract(batch)
  processed += batch.count

  logger.info "Progress: #{processed}/#{total} (#{(processed.to_f/total*100).round(1)}%)"
end
```

### 4. Use Appropriate Extractors

```ruby
# LLM for complex documents
complex_docs = sources.select { |s| s.content.length > 1000 }
facts.batch_extract(complex_docs.map(&:id), extractor: :llm)

# Rule-based for simple, structured content
simple_docs = sources.select { |s| s.content.length <= 1000 }
facts.batch_extract(simple_docs.map(&:id), extractor: :rule_based)
```
