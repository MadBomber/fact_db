# frozen_string_literal: true

# IngestReporter - Progress reporting for document ingestion
#
# This class provides clear, non-blocking feedback during long ingestion
# processes. It uses a single-line status approach that updates in place,
# showing users that work is happening without cluttering the terminal.
#
# Usage:
#   reporter = IngestReporter.new
#   reporter.start_ingestion(total_files: 10)
#   reporter.file_started("document.md", 1, 10)
#   reporter.section_started("Introduction", 1, 5)
#   reporter.extraction_started
#   reporter.extraction_progress  # call periodically during LLM calls
#   reporter.extraction_completed(facts_count: 3, entities_count: 5)
#   reporter.section_completed
#   reporter.file_completed(facts: 8, entities: 12, errors: 0, skipped: 1)
#   reporter.finish_ingestion
#
# Customization:
#   Subclass and override methods to customize output format, or set
#   output: to a different IO object for logging.

class IngestReporter
  SPINNER_CHARS = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

  attr_reader :output, :total_files, :total_facts, :total_entities, :total_errors

  def initialize(output: $stdout, color: true)
    @output = output
    @color = color && output.respond_to?(:tty?) && output.tty?
    @spinner_index = 0
    @extraction_start_time = nil
    @file_start_time = nil
    @ingestion_start_time = nil
    @current_file = nil
    @current_file_index = 0
    @current_section = nil
    @current_section_index = 0
    @total_sections = 0
    @total_files = 0
    @total_facts = 0
    @total_entities = 0
    @total_errors = 0
    @line_length = 0
  end

  # Called once at the start of the ingestion process
  def start_ingestion(total_files:, source_path:)
    @total_files = total_files
    @ingestion_start_time = Time.now
    @total_facts = 0
    @total_entities = 0
    @total_errors = 0

    write_line ""
    write_line "Starting ingestion: #{total_files} file(s) from #{source_path}"
    write_line ""
  end

  # Called when a new file begins processing
  def file_started(filename, index, total)
    @current_file = filename
    @current_file_index = index
    @total_files = total
    @file_start_time = Time.now
    @file_facts = 0
    @file_entities = 0
    @file_errors = 0
    @file_skipped = 0

    update_status
  end

  # Called when a new section within a file begins
  def section_started(section_ref, index, total)
    @current_section = section_ref
    @current_section_index = index
    @total_sections = total

    update_status
  end

  # Called when a section is skipped (already processed)
  def section_skipped(section_ref)
    @file_skipped += 1
  end

  # Called when LLM extraction begins
  def extraction_started
    @extraction_start_time = Time.now
    update_status
  end

  # Called periodically during LLM extraction to show activity
  # Returns immediately - call this in a loop or timer
  def extraction_progress
    @spinner_index = (@spinner_index + 1) % SPINNER_CHARS.length
    update_status(extracting: true)
  end

  # Called when extraction completes for a section
  def extraction_completed(facts_count:, entities_count:)
    @file_facts += facts_count
    @file_entities += entities_count
    @total_facts += facts_count
    @total_entities += entities_count
    @extraction_start_time = nil

    update_status
  end

  # Called when a section finishes processing
  def section_completed
    @current_section = nil
  end

  # Called when an error occurs
  def error_occurred(error, context: nil)
    @file_errors += 1
    @total_errors += 1

    clear_line
    error_msg = context ? "#{context}: #{error.message}" : error.message
    write_line colorize("  ✗ Error: #{truncate(error_msg, 70)}", :red)
  end

  # Called when a file finishes processing
  def file_completed(facts:, entities:, errors:, skipped:)
    elapsed = Time.now - @file_start_time
    clear_line

    status_parts = ["#{facts} facts", "#{entities} entities"]
    status_parts << colorize("#{errors} errors", :red) if errors > 0
    status_parts << "#{skipped} skipped" if skipped > 0
    status_parts << format_duration(elapsed)

    symbol = errors > 0 ? colorize("✗", :red) : colorize("✓", :green)
    write_line "#{symbol} #{@current_file}: #{status_parts.join(", ")}"

    @current_file = nil
    @current_section = nil
  end

  # Called when all files are processed
  def finish_ingestion
    elapsed = Time.now - @ingestion_start_time
    clear_line

    write_line ""
    write_line "─" * 50
    write_line "Ingestion complete in #{format_duration(elapsed)}"
    write_line "  Files processed: #{@current_file_index}"
    write_line "  Facts extracted: #{@total_facts}"
    write_line "  Entities found:  #{@total_entities}"
    write_line colorize("  Errors: #{@total_errors}", :red) if @total_errors > 0
    write_line ""
  end

  # Called to report files that were already processed
  def report_already_processed(count)
    return if count == 0

    write_line colorize("  (#{count} file(s) already processed, skipping)", :dim)
  end

  # Called when no files need processing
  def no_files_to_process
    write_line colorize("  All files already processed. Use --rebuild to reprocess.", :dim)
  end

  private

  def update_status(extracting: false)
    clear_line

    parts = []

    # File progress
    parts << "[#{@current_file_index}/#{@total_files}]"

    # Current file (truncated)
    if @current_file
      parts << truncate(@current_file, 25)
    end

    # Section progress
    if @current_section && @total_sections > 0
      parts << "#{@current_section_index}/#{@total_sections} sections"
    end

    # Extraction indicator with spinner and elapsed time
    if extracting && @extraction_start_time
      elapsed = Time.now - @extraction_start_time
      spinner = SPINNER_CHARS[@spinner_index]
      parts << "#{spinner} extracting (#{format_duration(elapsed)})"
    end

    # Running totals
    if @total_facts > 0 || @file_facts > 0
      parts << "#{@total_facts} facts"
      parts << "#{@total_entities} entities"
    end

    status = parts.join(" │ ")
    write_status(status)
  end

  def write_status(text)
    @line_length = text.length
    @output.print "\r#{text}"
    @output.flush
  end

  def clear_line
    return if @line_length == 0

    @output.print "\r#{" " * @line_length}\r"
    @output.flush
    @line_length = 0
  end

  def write_line(text)
    clear_line
    @output.puts text
  end

  def format_duration(seconds)
    if seconds < 60
      format("%.1fs", seconds)
    elsif seconds < 3600
      minutes = (seconds / 60).to_i
      secs = (seconds % 60).to_i
      "#{minutes}m #{secs}s"
    else
      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      "#{hours}h #{minutes}m"
    end
  end

  def truncate(text, length)
    return text if text.length <= length

    text[0, length - 1] + "…"
  end

  def colorize(text, color)
    return text unless @color

    codes = {
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      dim: "\e[2m",
      reset: "\e[0m"
    }

    "#{codes[color]}#{text}#{codes[:reset]}"
  end
end


# QuietReporter - Minimal output for scripting/automation
#
# Use this when you want minimal output, e.g., in CI pipelines
# or when redirecting output to a file.
class QuietReporter < IngestReporter
  def start_ingestion(total_files:, source_path:)
    @total_files = total_files
    @ingestion_start_time = Time.now
    @total_facts = 0
    @total_entities = 0
    @total_errors = 0
  end

  def file_started(filename, index, total)
    @current_file = filename
    @current_file_index = index
    @file_start_time = Time.now
  end

  def section_started(section_ref, index, total); end
  def section_skipped(section_ref); end
  def extraction_started; end
  def extraction_progress; end
  def extraction_completed(facts_count:, entities_count:)
    @total_facts += facts_count
    @total_entities += entities_count
  end
  def section_completed; end

  def error_occurred(error, context: nil)
    @total_errors += 1
    error_msg = context ? "#{context}: #{error.message}" : error.message
    @output.puts "ERROR: #{error_msg}"
  end

  def file_completed(facts:, entities:, errors:, skipped:)
    @output.puts "#{@current_file}: #{facts} facts, #{entities} entities"
  end

  def finish_ingestion
    elapsed = Time.now - @ingestion_start_time
    @output.puts "Completed: #{@total_facts} facts, #{@total_entities} entities in #{format_duration(elapsed)}"
  end

  def report_already_processed(count); end
  def no_files_to_process
    @output.puts "All files already processed."
  end
end


# VerboseReporter - Detailed output for debugging
#
# Shows all details including section names and extraction timing.
class VerboseReporter < IngestReporter
  def section_started(section_ref, index, total)
    super
    write_line "    Section #{index}/#{total}: #{section_ref}"
  end

  def extraction_completed(facts_count:, entities_count:)
    elapsed = @extraction_start_time ? Time.now - @extraction_start_time : 0
    super
    write_line "      Extracted #{facts_count} facts, #{entities_count} entities (#{format_duration(elapsed)})"
  end

  def error_occurred(error, context: nil)
    super
    write_line "      #{error.backtrace&.first}" if error.backtrace
  end
end
