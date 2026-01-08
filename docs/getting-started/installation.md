# Installation

## Requirements

- Ruby >= 3.0.0
- PostgreSQL >= 14 with pgvector extension
- Bundler

## Install the Gem

Add FactDb to your Gemfile:

```ruby
gem 'fact_db'
```

Then install:

```bash
bundle install
```

Or install directly:

```bash
gem install fact_db
```

## Install pgvector

FactDb uses pgvector for semantic search. Install the PostgreSQL extension:

=== "macOS (Homebrew)"

    ```bash
    brew install pgvector
    ```

=== "Ubuntu/Debian"

    ```bash
    sudo apt install postgresql-14-pgvector
    ```

=== "From Source"

    ```bash
    git clone https://github.com/pgvector/pgvector.git
    cd pgvector
    make
    sudo make install
    ```

Then enable the extension in your database:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

## Optional Dependencies

### LLM Extraction

For LLM-powered fact extraction, add the ruby_llm gem:

```ruby
gem 'ruby_llm'
```

### Async Processing

For parallel pipeline processing with async fibers:

```ruby
gem 'async', '~> 2.0'
```

## Verify Installation

Create a simple test script:

```ruby
require 'fact_db'

puts "FactDb version: #{FactDb::VERSION}"
puts "Installation successful!"
```

Run it:

```bash
ruby test_install.rb
```

## Next Steps

- [Database Setup](database-setup.md) - Configure your database
- [Quick Start](quick-start.md) - Start using FactDb
