#!/usr/bin/env ruby
# frozen_string_literal: true

# HR System Example for FactDb
#
# This example demonstrates a practical HR knowledge management system:
# - Tracking employee information over time
# - Managing organizational hierarchy
# - Recording promotions, transfers, and departures
# - Auditing changes with temporal queries
# - Detecting conflicts in employee data

require "bundler/setup"
require "fact_db"

FactDb.configure do |config|
  config.database_url = ENV.fetch("DATABASE_URL", "postgres://#{ENV['USER']}@localhost/fact_db_demo")
  config.default_extractor = :manual
end

# Ensure database tables exist
FactDb::Database.migrate!

clock = FactDb.new
entity_service = clock.entity_service
fact_service = clock.fact_service
content_service = clock.content_service

puts "=" * 60
puts "HR Knowledge Management System Demo"
puts "=" * 60

# Section 1: Setup Company Structure
puts "\n--- Section 1: Setting Up Organization ---\n"

# Create the company
company = entity_service.create(
  "Innovate Corp",
  type: :organization,
  description: "Technology company specializing in AI solutions",
  attributes: { industry: "Technology", founded: "2010" }
)

# Create departments
engineering = entity_service.create(
  "Engineering Department",
  type: :organization,
  description: "Software engineering team",
  attributes: { parent: company.id }
)

product = entity_service.create(
  "Product Department",
  type: :organization,
  description: "Product management team",
  attributes: { parent: company.id }
)

hr_dept = entity_service.create(
  "Human Resources",
  type: :organization,
  description: "HR team",
  attributes: { parent: company.id }
)

puts "Created company: #{company.canonical_name}"
puts "Created departments: #{engineering.canonical_name}, #{product.canonical_name}, #{hr_dept.canonical_name}"

# Create locations
hq = entity_service.create(
  "San Francisco HQ",
  type: :place,
  aliases: ["SF Office", "Headquarters"],
  attributes: { city: "San Francisco", state: "CA" }
)

remote_office = entity_service.create(
  "Austin Office",
  type: :place,
  aliases: ["Austin TX Office"],
  attributes: { city: "Austin", state: "TX" }
)

puts "Created locations: #{hq.canonical_name}, #{remote_office.canonical_name}"

# Section 2: Create Employee Profiles
puts "\n--- Section 2: Creating Employee Profiles ---\n"

employees = {}

# CEO
employees[:ceo] = entity_service.create(
  "Katherine Rodriguez",
  type: :person,
  aliases: ["Kate Rodriguez", "K. Rodriguez"],
  attributes: { employee_id: "EMP001", email: "krodriguez@innovatecorp.com" },
  description: "Chief Executive Officer"
)

# VP Engineering
employees[:vp_eng] = entity_service.create(
  "Marcus Chen",
  type: :person,
  aliases: ["Marc Chen"],
  attributes: { employee_id: "EMP002", email: "mchen@innovatecorp.com" },
  description: "VP of Engineering"
)

# Senior Engineer
employees[:senior_eng] = entity_service.create(
  "Priya Sharma",
  type: :person,
  attributes: { employee_id: "EMP003", email: "psharma@innovatecorp.com" },
  description: "Senior Software Engineer"
)

# Junior Engineer (will be promoted)
employees[:junior_eng] = entity_service.create(
  "Alex Kim",
  type: :person,
  attributes: { employee_id: "EMP004", email: "akim@innovatecorp.com" },
  description: "Software Engineer"
)

# Product Manager
employees[:pm] = entity_service.create(
  "Jordan Taylor",
  type: :person,
  attributes: { employee_id: "EMP005", email: "jtaylor@innovatecorp.com" },
  description: "Product Manager"
)

# HR Manager
employees[:hr_mgr] = entity_service.create(
  "Michelle Brown",
  type: :person,
  attributes: { employee_id: "EMP006", email: "mbrown@innovatecorp.com" },
  description: "HR Manager"
)

puts "Created #{employees.length} employee profiles"

# Section 3: Record Initial Employment Facts
puts "\n--- Section 3: Recording Employment History ---\n"

# Ingest an onboarding document
onboarding_doc = content_service.create(
  <<~DOC,
    EMPLOYEE ONBOARDING RECORDS - 2020-2024

    Katherine Rodriguez - Hired as CEO on January 15, 2020
    Marcus Chen - Hired as Engineering Manager on March 1, 2020
    Priya Sharma - Hired as Software Engineer on June 15, 2021
    Alex Kim - Hired as Junior Developer on September 1, 2023
    Jordan Taylor - Hired as Associate PM on February 1, 2022
    Michelle Brown - Hired as HR Coordinator on April 1, 2021
  DOC
  type: :document,
  title: "Historical Onboarding Records"
)

# CEO facts
ceo_employment = fact_service.create(
  "Katherine Rodriguez is CEO of Innovate Corp",
  valid_at: Date.new(2020, 1, 15),
  mentions: [
    { entity_id: employees[:ceo].id, role: :subject, text: "Katherine Rodriguez" },
    { entity_id: company.id, role: :object, text: "Innovate Corp" }
  ]
)
ceo_employment.add_source(content: onboarding_doc, type: :primary)

ceo_location = fact_service.create(
  "Katherine Rodriguez works at San Francisco HQ",
  valid_at: Date.new(2020, 1, 15),
  mentions: [
    { entity_id: employees[:ceo].id, role: :subject, text: "Katherine Rodriguez" },
    { entity_id: hq.id, role: :location, text: "San Francisco HQ" }
  ]
)

# VP Engineering - with promotion history
vp_eng_original = fact_service.create(
  "Marcus Chen is Engineering Manager at Innovate Corp",
  valid_at: Date.new(2020, 3, 1),
  invalid_at: Date.new(2023, 1, 1),
  status: :superseded,
  mentions: [
    { entity_id: employees[:vp_eng].id, role: :subject, text: "Marcus Chen" },
    { entity_id: company.id, role: :object, text: "Innovate Corp" }
  ]
)

vp_eng_current = fact_service.create(
  "Marcus Chen is VP of Engineering at Innovate Corp",
  valid_at: Date.new(2023, 1, 1),
  mentions: [
    { entity_id: employees[:vp_eng].id, role: :subject, text: "Marcus Chen" },
    { entity_id: company.id, role: :object, text: "Innovate Corp" }
  ]
)

# Other employees
fact_service.create(
  "Priya Sharma is Senior Software Engineer at Innovate Corp",
  valid_at: Date.new(2021, 6, 15),
  mentions: [
    { entity_id: employees[:senior_eng].id, role: :subject, text: "Priya Sharma" },
    { entity_id: engineering.id, role: :object, text: "Engineering Department" }
  ]
)

fact_service.create(
  "Priya Sharma reports to Marcus Chen",
  valid_at: Date.new(2021, 6, 15),
  mentions: [
    { entity_id: employees[:senior_eng].id, role: :subject, text: "Priya Sharma" },
    { entity_id: employees[:vp_eng].id, role: :object, text: "Marcus Chen" }
  ]
)

junior_original = fact_service.create(
  "Alex Kim is Junior Developer at Innovate Corp",
  valid_at: Date.new(2023, 9, 1),
  mentions: [
    { entity_id: employees[:junior_eng].id, role: :subject, text: "Alex Kim" },
    { entity_id: engineering.id, role: :object, text: "Engineering Department" }
  ]
)

fact_service.create(
  "Jordan Taylor is Product Manager at Innovate Corp",
  valid_at: Date.new(2022, 2, 1),
  mentions: [
    { entity_id: employees[:pm].id, role: :subject, text: "Jordan Taylor" },
    { entity_id: product.id, role: :object, text: "Product Department" }
  ]
)

hr_original = fact_service.create(
  "Michelle Brown is HR Coordinator at Innovate Corp",
  valid_at: Date.new(2021, 4, 1),
  invalid_at: Date.new(2024, 7, 1),
  status: :superseded,
  mentions: [
    { entity_id: employees[:hr_mgr].id, role: :subject, text: "Michelle Brown" },
    { entity_id: hr_dept.id, role: :object, text: "Human Resources" }
  ]
)

hr_current = fact_service.create(
  "Michelle Brown is HR Manager at Innovate Corp",
  valid_at: Date.new(2024, 7, 1),
  mentions: [
    { entity_id: employees[:hr_mgr].id, role: :subject, text: "Michelle Brown" },
    { entity_id: hr_dept.id, role: :object, text: "Human Resources" }
  ]
)

puts "Recorded employment history facts"

# Section 4: Process a Promotion
puts "\n--- Section 4: Processing a Promotion ---\n"

# Ingest the promotion memo
promotion_memo = content_service.create(
  <<~MEMO,
    INTERNAL MEMO
    Date: January 8, 2026
    From: Marcus Chen, VP Engineering
    Subject: Promotion Announcement

    I am pleased to announce that Alex Kim has been promoted to
    Software Engineer, effective January 15, 2026. Alex has demonstrated
    exceptional growth and technical skills during their time as
    Junior Developer.

    Congratulations Alex!
  MEMO
  type: :document,
  title: "Promotion Memo - Alex Kim"
)

# Supersede the old fact
promoted_fact = fact_service.supersede(
  junior_original.id,
  "Alex Kim is Software Engineer at Innovate Corp",
  valid_at: Date.new(2026, 1, 15),
  mentions: [
    { entity_id: employees[:junior_eng].id, role: :subject, text: "Alex Kim" },
    { entity_id: engineering.id, role: :object, text: "Engineering Department" }
  ]
)
promoted_fact.add_source(content: promotion_memo, type: :primary)

puts "Promoted Alex Kim from Junior Developer to Software Engineer"
puts "Previous fact (#{junior_original.id}) now superseded"
puts "New fact ID: #{promoted_fact.id}"

# Section 5: Record a Transfer
puts "\n--- Section 5: Recording a Transfer ---\n"

# Jordan is transferring to Austin
transfer_memo = content_service.create(
  <<~MEMO,
    INTERNAL MEMO
    Date: January 10, 2026
    Subject: Transfer Notice - Jordan Taylor

    Jordan Taylor will be transferring to our Austin office
    effective February 1, 2026. Jordan will continue in the
    Product Manager role but will lead our Texas expansion efforts.
  MEMO
  type: :document,
  title: "Transfer Notice - Jordan Taylor"
)

# Old location fact
jordan_sf_location = fact_service.create(
  "Jordan Taylor works at San Francisco HQ",
  valid_at: Date.new(2022, 2, 1),
  invalid_at: Date.new(2026, 2, 1),
  status: :superseded,
  mentions: [
    { entity_id: employees[:pm].id, role: :subject, text: "Jordan Taylor" },
    { entity_id: hq.id, role: :location, text: "San Francisco HQ" }
  ]
)

# New location fact
jordan_austin_location = fact_service.create(
  "Jordan Taylor works at Austin Office",
  valid_at: Date.new(2026, 2, 1),
  mentions: [
    { entity_id: employees[:pm].id, role: :subject, text: "Jordan Taylor" },
    { entity_id: remote_office.id, role: :location, text: "Austin Office" }
  ]
)
jordan_austin_location.add_source(content: transfer_memo, type: :primary)

puts "Recorded Jordan Taylor's transfer to Austin Office"

# Section 6: Query Employee Information
puts "\n--- Section 6: HR Queries ---\n"

# Current state of all employees
puts "\nCurrent Employee Status:"
puts "-" * 50

employees.each do |key, employee|
  puts "\n#{employee.canonical_name}:"
  current_facts = fact_service.current_facts(entity: employee.id)
  current_facts.each do |fact|
    puts "  - #{fact.fact_text}"
  end
end

# Section 7: Historical Query
puts "\n--- Section 7: Historical Employee Query ---\n"

# What was Alex Kim's role in December 2024?
puts "\nAlex Kim's facts as of December 2024:"
past_facts = fact_service.facts_at(Date.new(2024, 12, 1), entity: employees[:junior_eng].id)
past_facts.each { |f| puts "  - #{f.fact_text}" }

# What is Alex Kim's role now?
puts "\nAlex Kim's facts as of today:"
current_facts = fact_service.facts_at(Date.today, entity: employees[:junior_eng].id)
current_facts.each { |f| puts "  - #{f.fact_text}" }

# Section 8: Organization Chart Query
puts "\n--- Section 8: Organization Chart ---\n"

puts "\nReporting relationships:"
# Find all "reports to" facts
reporting_facts = fact_service.search("reports to")
reporting_facts.each { |f| puts "  #{f.fact_text}" }

puts "\nEngineering Department members:"
engineering_facts = fact_service.current_facts(entity: engineering.id)
engineering_facts.each { |f| puts "  #{f.fact_text}" }

# Section 9: Employee Timeline
puts "\n--- Section 9: Marcus Chen Career Timeline ---\n"

timeline = fact_service.timeline(
  entity_id: employees[:vp_eng].id,
  from: Date.new(2020, 1, 1),
  to: Date.today
)

timeline.each do |entry|
  end_date = entry[:invalid_at]&.strftime("%Y-%m-%d") || "present"
  status_marker = entry[:status] != "canonical" ? " [#{entry[:status]}]" : ""
  puts "  #{entry[:valid_at].strftime('%Y-%m-%d')} - #{end_date}: #{entry[:fact_text]}#{status_marker}"
end

# Section 10: Audit Trail
puts "\n--- Section 10: Audit Trail for Alex Kim ---\n"

alex_facts = FactDb::Models::Fact.joins(:entity_mentions)
  .where(entity_mentions: { entity_id: employees[:junior_eng].id })
  .order(:created_at)

puts "Complete fact history:"
alex_facts.each do |fact|
  status_info = fact.status != "canonical" ? " [#{fact.status}]" : ""
  validity = fact.invalid_at ? "#{fact.valid_at} - #{fact.invalid_at}" : "#{fact.valid_at} - present"
  puts "  [#{validity}] #{fact.fact_text}#{status_info}"

  fact.fact_sources.each do |source|
    puts "    Source: #{source.content.title} (#{source.source_type})"
  end
end

# Section 11: Statistics
puts "\n--- Section 11: HR System Statistics ---\n"

puts "Total employees tracked: #{entity_service.people.count}"
puts "Total departments: #{entity_service.organizations.where("description LIKE ?", "%team%").count}"
puts "Total employment facts: #{fact_service.stats[:total]}"
puts "Current facts: #{FactDb::Models::Fact.currently_valid.count}"
puts "Historical facts: #{FactDb::Models::Fact.historical.count}"
puts "Documents processed: #{content_service.stats[:total]}"

puts "\n" + "=" * 60
puts "HR System Demo Complete!"
puts "=" * 60
