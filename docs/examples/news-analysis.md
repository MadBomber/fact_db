# News Analysis Example

Extract and track facts from news articles over time.

## Scenario

A news monitoring system that extracts facts from articles and tracks how information about companies and people changes over time.

## Setup

```ruby
require 'fact_db'

FactDb.configure do |config|
  config.database_url = ENV['DATABASE_URL']
  config.llm_provider = :openai
  config.llm_api_key = ENV['OPENAI_API_KEY']
end

facts = FactDb.new
```

## Ingest News Articles

```ruby
# Article 1: CEO Announcement
article1 = facts.ingest(
  <<~TEXT,
    TechCorp Appoints New CEO

    San Francisco, Jan 15, 2024 - TechCorp announced today that
    Jane Williams has been appointed as Chief Executive Officer,
    effective immediately. Williams previously served as COO at
    InnovateTech for 8 years.

    "We are thrilled to welcome Jane to lead TechCorp into its
    next chapter," said Board Chairman Robert Chen.

    Williams succeeds Michael Johnson, who is retiring after
    15 years at the helm.
  TEXT
  type: :article,
  title: "TechCorp Appoints New CEO",
  source_uri: "https://news.example.com/techcorp-new-ceo",
  captured_at: Date.parse("2024-01-15"),
  metadata: {
    source: "Tech News Daily",
    author: "Sarah Reporter",
    category: "Business"
  }
)

# Article 2: Earnings Report
article2 = facts.ingest(
  <<~TEXT,
    TechCorp Reports Record Q4 Earnings

    San Francisco, Feb 1, 2024 - TechCorp reported quarterly
    revenue of $5.2 billion, up 23% year-over-year. Net income
    reached $800 million.

    "Our cloud division continues to drive growth," said CEO
    Jane Williams in her first earnings call since taking over.

    The company also announced plans to acquire DataFlow Inc
    for $1.2 billion, expected to close in Q2 2024.
  TEXT
  type: :article,
  title: "TechCorp Reports Record Q4 Earnings",
  source_uri: "https://news.example.com/techcorp-q4-earnings",
  captured_at: Date.parse("2024-02-01"),
  metadata: { source: "Financial Times", category: "Earnings" }
)

# Article 3: Acquisition Update
article3 = facts.ingest(
  <<~TEXT,
    TechCorp-DataFlow Deal Falls Through

    San Francisco, Apr 15, 2024 - TechCorp announced it has
    terminated its planned acquisition of DataFlow Inc, citing
    regulatory concerns.

    "After careful consideration, we have decided not to proceed
    with the acquisition," said TechCorp CEO Jane Williams.
  TEXT
  type: :article,
  title: "TechCorp-DataFlow Deal Falls Through",
  source_uri: "https://news.example.com/techcorp-dataflow-cancelled",
  captured_at: Date.parse("2024-04-15"),
  metadata: { source: "Business Wire", category: "M&A" }
)
```

## Extract Facts with LLM

```ruby
# Process all articles
[article1, article2, article3].each do |article|
  puts "Processing: #{article.title}"
  extracted = facts.extract_facts(article.id, extractor: :llm)
  puts "  Extracted #{extracted.count} facts"
end
```

## Review Extracted Entities

```ruby
# List all extracted entities
puts "\nExtracted Entities:"
FactDb::Models::Entity.all.each do |entity|
  puts "  #{entity.canonical_name} (#{entity.entity_type})"
end
```

## Query Facts by Topic

```ruby
# CEO-related facts
puts "\nCEO Facts:"
facts.query_facts(topic: "CEO").each do |fact|
  puts "  #{fact.valid_at.to_date}: #{fact.fact_text}"
end

# Acquisition facts
puts "\nAcquisition Facts:"
facts.query_facts(topic: "acquisition").each do |fact|
  puts "  #{fact.valid_at.to_date}: #{fact.fact_text}"
end
```

## Track Entity Over Time

```ruby
# Find TechCorp entity
techcorp = facts.resolve_entity("TechCorp", type: :organization)

# Timeline of TechCorp facts
puts "\nTechCorp Timeline:"
facts.timeline_for(techcorp.id).each do |fact|
  source = fact.fact_sources.first&.content&.title || "Unknown"
  puts "  #{fact.valid_at.to_date}: #{fact.fact_text}"
  puts "    Source: #{source}"
end
```

## Handle Superseded Information

```ruby
# The acquisition fact from article2 should be superseded by article3

# Find the original acquisition fact
acquisition_fact = FactDb::Models::Fact
  .search_text("acquire DataFlow")
  .canonical
  .first

if acquisition_fact
  # Supersede with cancelled status
  facts.fact_service.resolver.supersede(
    acquisition_fact.id,
    "TechCorp cancelled its planned acquisition of DataFlow Inc",
    valid_at: Date.parse("2024-04-15")
  )

  puts "\nAcquisition status updated:"
  puts "  Original: #{acquisition_fact.reload.fact_text} (#{acquisition_fact.status})"
  puts "  Updated: #{acquisition_fact.superseded_by.fact_text}"
end
```

## Corroborate Facts

```ruby
# If multiple articles confirm the same fact
ceo_facts = FactDb::Models::Fact
  .search_text("Jane Williams CEO")
  .canonical
  .to_a

if ceo_facts.count > 1
  primary = ceo_facts.first
  ceo_facts[1..].each do |corroborating|
    facts.fact_service.resolver.corroborate(primary.id, corroborating.id)
  end
  puts "\nCEO fact corroborated by #{ceo_facts.count} sources"
end
```

## Generate Company Report

```ruby
def company_report(facts, company_name)
  company = facts.resolve_entity(company_name, type: :organization)
  return nil unless company

  current_facts = facts.current_facts_for(company.id)

  {
    company: company.canonical_name,
    current_facts: current_facts.map(&:fact_text),
    leadership: extract_leadership(current_facts),
    timeline: facts.timeline_for(company.id).map { |f|
      {
        date: f.valid_at,
        fact: f.fact_text,
        source: f.fact_sources.first&.content&.title
      }
    }
  }
end

def extract_leadership(facts)
  leadership = {}
  facts.each do |fact|
    if fact.fact_text =~ /CEO/
      leadership[:ceo] = fact.entity_mentions.find { |m| m.mention_role == "subject" }&.entity&.canonical_name
    end
  end
  leadership
end

report = company_report(facts, "TechCorp")
puts JSON.pretty_generate(report)
```

## Batch Process News Feed

```ruby
def process_news_feed(facts, articles)
  content_ids = articles.map do |article|
    content = facts.ingest(
      article[:text],
      type: :article,
      title: article[:title],
      source_uri: article[:url],
      captured_at: article[:published_at]
    )
    content.id
  end

  # Parallel extraction
  results = facts.batch_extract(content_ids, extractor: :llm)

  {
    processed: results.count,
    successful: results.count { |r| r[:error].nil? },
    total_facts: results.sum { |r| r[:facts].count }
  }
end

# Example usage
news_feed = [
  { title: "Article 1", text: "...", url: "...", published_at: Time.now },
  { title: "Article 2", text: "...", url: "...", published_at: Time.now }
]

stats = process_news_feed(facts, news_feed)
puts "Processed #{stats[:processed]} articles, extracted #{stats[:total_facts]} facts"
```

## Monitor Specific Topics

```ruby
def monitor_topic(facts, topic, since: 1.week.ago)
  matching = FactDb::Models::Fact
    .search_text(topic)
    .where("created_at > ?", since)
    .order(created_at: :desc)

  {
    topic: topic,
    new_facts: matching.count,
    facts: matching.map { |f|
      {
        text: f.fact_text,
        date: f.valid_at,
        source: f.fact_sources.first&.content&.title,
        entities: f.entity_mentions.map { |m| m.entity.canonical_name }
      }
    }
  }
end

# Monitor acquisitions
acquisition_updates = monitor_topic(facts, "acquisition")
puts "Recent acquisition news: #{acquisition_updates[:new_facts]} facts"
```
