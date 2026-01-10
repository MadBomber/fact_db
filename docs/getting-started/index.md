# Getting Started

This section will help you get FactDb up and running in your Ruby application.

## Prerequisites

Before installing FactDb, ensure you have:

- **Ruby 3.0+** - FactDb requires Ruby 3.0 or later
- **PostgreSQL 14+** - With the pgvector extension installed
- **Bundler** - For dependency management

## Quick Navigation

<div class="grid cards" markdown>

-   :material-download:{ .lg .middle } **Installation**

    ---

    Install FactDb and its dependencies

    [:octicons-arrow-right-24: Installation Guide](installation.md)

-   :material-rocket-launch:{ .lg .middle } **Quick Start**

    ---

    Get up and running in 5 minutes

    [:octicons-arrow-right-24: Quick Start](quick-start.md)

-   :material-database:{ .lg .middle } **Database Setup**

    ---

    Configure PostgreSQL and run migrations

    [:octicons-arrow-right-24: Database Setup](database-setup.md)

</div>

## Overview

Getting started with FactDb involves three steps:

1. **Install the gem** - Add FactDb to your Gemfile
2. **Set up the database** - Create tables and enable pgvector
3. **Configure** - Set database URL and optional LLM settings

Once configured, you can start ingesting content and extracting facts:

```ruby
require 'fact_db'

# Configure
FactDb.configure do |config|
  config.database.url = ENV['DATABASE_URL']
end

# Create a facts instance
facts = FactDb.new

# Ingest content
content = facts.ingest("Important information...", type: :document)

# Extract and query facts
extracted = facts.extract_facts(content.id)
```

Continue to the [Installation Guide](installation.md) to begin.
