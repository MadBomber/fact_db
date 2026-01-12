# Pipeline

Pipelines provide concurrent processing for batch operations using SimpleFlow.

## Available Pipelines

- [ExtractionPipeline](extraction.md) - Concurrent fact extraction
- [ResolutionPipeline](resolution.md) - Parallel entity resolution

## SimpleFlow Integration

Pipelines are built on the `simple_flow` gem:

```ruby
require 'simple_flow'

pipeline = SimpleFlow::Pipeline.new do
  step ->(result) { result.continue(transformed_value) }
  step ->(result) { result.continue(more_transformation) }
end

result = pipeline.call(SimpleFlow::Result.new(initial_value))
```

## Pipeline Pattern

All pipelines follow a common structure:

```ruby
class SomePipeline
  attr_reader :config

  def initialize(config = FactDb.config)
    @config = config
  end

  def process(items, **options)
    # Sequential processing
  end

  def process_parallel(items, **options)
    # Parallel processing
  end
end
```

## Result Structure

Pipeline results follow a consistent format:

```ruby
{
  source_id: 123,           # Item identifier
  facts: [<Fact>, ...],     # Extracted/resolved items
  error: nil                # Error message if failed
}
```

## Error Handling

Pipelines handle errors gracefully:

```ruby
results = pipeline.process_parallel(items)

successful = results.select { |r| r[:error].nil? }
failed = results.reject { |r| r[:error].nil? }

failed.each do |result|
  logger.error "Failed: #{result[:error]}"
end
```
