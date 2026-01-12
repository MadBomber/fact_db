# RuleBasedExtractor

Pattern-based fact extraction using regular expressions.

## Class: `FactDb::Extractors::RuleBasedExtractor`

```ruby
extractor = FactDb::Extractors::RuleBasedExtractor.new(config)
```

## Methods

### extract

```ruby
def extract(content)
```

Extract facts using pattern matching.

**Returns:** `Array<Models::Fact>`

## Built-in Patterns

The extractor includes patterns for common fact types:

### Employment Events

```ruby
# "X joined Y"
/(?<person>\w+(?:\s+\w+)*)\s+joined\s+(?<org>\w+(?:\s+\w+)*)/i

# "X left Y"
/(?<person>\w+(?:\s+\w+)*)\s+left\s+(?<org>\w+(?:\s+\w+)*)/i

# "X was hired by Y"
/(?<person>\w+(?:\s+\w+)*)\s+was\s+hired\s+by\s+(?<org>\w+(?:\s+\w+)*)/i
```

### Title Changes

```ruby
# "X is/was the Y"
/(?<person>\w+(?:\s+\w+)*)\s+(?:is|was)\s+(?:the\s+)?(?<title>[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/

# "X promoted to Y"
/(?<person>\w+(?:\s+\w+)*)\s+(?:was\s+)?promoted\s+to\s+(?<title>[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/i
```

### Date Patterns

```ruby
# "on January 10, 2024"
/on\s+(?<month>\w+)\s+(?<day>\d{1,2}),?\s+(?<year>\d{4})/i

# "in Q4 2024"
/in\s+Q(?<quarter>\d)\s+(?<year>\d{4})/i

# ISO dates
/(?<date>\d{4}-\d{2}-\d{2})/
```

## Usage Example

```ruby
extractor = RuleBasedExtractor.new(config)

source = Models::Source.create!(
  content: "Paula Chen joined Microsoft on January 10, 2024 as Principal Engineer.",
  type: "announcement",
  captured_at: Time.current
)

facts = extractor.extract(source)
# Returns facts about:
# - Paula joining Microsoft
# - Paula's title as Principal Engineer
# - Date: January 10, 2024
```

## Adding Custom Patterns

Extend the extractor with custom patterns:

```ruby
class CustomRuleExtractor < FactDb::Extractors::RuleBasedExtractor
  CUSTOM_PATTERNS = [
    {
      pattern: /revenue\s+of\s+\$(?<amount>[\d,]+)/i,
      type: :financial,
      handler: :extract_revenue
    }
  ]

  def extract(content)
    facts = super(content)
    facts + extract_custom_patterns(content)
  end

  private

  def extract_custom_patterns(source)
    facts = []
    CUSTOM_PATTERNS.each do |rule|
      source.content.scan(rule[:pattern]) do |match|
        facts << send(rule[:handler], match, source)
      end
    end
    facts
  end

  def extract_revenue(match, source)
    Models::Fact.create!(
      fact_text: "Revenue of $#{match[:amount]}",
      valid_at: source.captured_at,
      extraction_method: "rule_based",
      # ...
    )
  end
end
```

## Advantages

- Fast execution
- No external dependencies
- Predictable results
- Works offline
- Zero cost

## Disadvantages

- Limited to defined patterns
- Misses implicit facts
- Requires pattern maintenance
- May produce false positives

## Best Practices

### 1. Combine with LLM

```ruby
# Use rule-based for structured content
if content.type == "form"
  facts = rule_extractor.extract(content)
else
  facts = llm_extractor.extract(content)
end
```

### 2. Validate Matches

```ruby
facts = extractor.extract(content)
facts.select { |f| f.confidence > 0.8 }
```

### 3. Log Unmatched Sources

```ruby
facts = extractor.extract(source)
if facts.empty?
  logger.info "No patterns matched for source #{source.id}"
end
```
