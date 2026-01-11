# frozen_string_literal: true

# Common utilities for FactDb demo programs
#
# Usage: require_relative "utilities"
#
# This file provides:
# - Environment setup (ensures FDB_ENV=demo)
# - Database reset before each demo
# - Common output formatting methods

module DemoUtilities
  SEPARATOR_WIDTH = 60

  class << self
    # Setup the demo environment and reset the database
    # Call this at the start of each demo
    def setup!(demo_name = nil)
      ensure_demo_environment!
      reset_demo_database!
      require_fact_db!

      if demo_name
        header(demo_name)
      end
    end

    # Setup for CLI tools - sets environment but does NOT reset database
    # Use this for utility scripts that inspect/query existing data
    def cli_setup!(tool_name = nil)
      ensure_demo_environment!
      require_fact_db!
      FactDb::Database.establish_connection!

      if tool_name
        header(tool_name)
      end
    end

    # Ensure FDB_ENV is set to "demo"
    def ensure_demo_environment!
      ENV["FDB_ENV"] = "demo"
    end

    # Reset the demo database using rake task
    def reset_demo_database!
      project_root = File.expand_path("..", __dir__)

      # Run rake db:reset:demo quietly
      Dir.chdir(project_root) do
        system("bundle exec rake db:reset:demo > /dev/null 2>&1")
      end
    end

    # Require fact_db after environment is set
    def require_fact_db!
      require "bundler/setup"
      require "fact_db"
    end

    # Print a major header (demo title)
    def header(title)
      puts separator
      puts title
      puts separator
    end

    # Print a section header
    def section(title)
      str     = "--- #{title} ---"
      wrapper = str[0] * str.length
      puts "\n#{wrapper}\n#{str}\n#{wrapper}"
    end

    # Print a subsection header
    def subsection(title)
      puts "\n#{title}:"
    end

    # Print the demo completion footer
    def footer(title = "Demo Complete!")
      puts "\n" + separator
      puts title
      puts separator
    end

    # Print a separator line
    def separator
      "=" * SEPARATOR_WIDTH
    end

    # Print a list item
    def list_item(text, indent: 2)
      puts "#{" " * indent}- #{text}"
    end

    # Print an indented line
    def indent(text, level: 1)
      puts "#{"  " * level}#{text}"
    end

    # Print a key-value pair
    def kv(key, value, indent_level: 1)
      puts "#{"  " * indent_level}#{key}: #{value}"
    end

    # Print multiple lines with consistent formatting
    def block(lines)
      puts lines.map { |line| "  #{line}" }.join("\n")
    end

    # Configure logging to a file based on demo filename
    def configure_logging(demo_file)
      log_path = File.join(File.dirname(demo_file), "#{File.basename(demo_file, '.rb')}.log")

      FactDb.configure do |config|
        config.logger = Logger.new(log_path)
      end
    end

    # Create a new FactDb instance with optional logging setup
    def create_fact_db(demo_file = nil)
      configure_logging(demo_file) if demo_file
      FactDb.new
    end
  end
end

##########################################################
# Convenience methods at top level for cleaner demo code
def demo_setup!(demo_name = nil)
  DemoUtilities.setup!(demo_name)
end

def demo_header(title)
  DemoUtilities.header(title)
end

def demo_section(title)
  DemoUtilities.section(title)
end

def demo_subsection(title)
  DemoUtilities.subsection(title)
end

def demo_footer(title = "Demo Complete!")
  DemoUtilities.footer(title)
end

def demo_separator
  DemoUtilities.separator
end

def demo_list_item(text, indent: 2)
  DemoUtilities.list_item(text, indent: indent)
end

def demo_indent(text, level: 1)
  DemoUtilities.indent(text, level: level)
end

def demo_kv(key, value, indent_level: 1)
  DemoUtilities.kv(key, value, indent_level: indent_level)
end

def demo_block(lines)
  DemoUtilities.block(lines)
end

def demo_configure_logging(demo_file)
  DemoUtilities.configure_logging(demo_file)
end

def demo_create_fact_db(demo_file = nil)
  DemoUtilities.create_fact_db(demo_file)
end

def cli_setup!(tool_name = nil)
  DemoUtilities.cli_setup!(tool_name)
end
