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

require_relative "utilities"

demo_setup!("HR Knowledge Management System Demo")
demo_configure_logging(__FILE__)

FactDb.configure do |config|
  config.default_extractor = :manual
end

facts = FactDb.new
entity_service = facts.entity_service
fact_service = facts.fact_service
source_service = facts.source_service

demo_section("Section 1: Setting Up Organization")

# Create the company
company = entity_service.create(
  "Innovate Corp",
  kind: :organization,
  description: "Technology company specializing in AI solutions",
  attributes: { industry: "Technology", founded: "2010" }
)

# Create departments
engineering = entity_service.create(
  "Engineering Department",
  kind: :organization,
  description: "Software engineering team",
  attributes: { parent: company.id }
)

product = entity_service.create(
  "Product Department",
  kind: :organization,
  description: "Product management team",
  attributes: { parent: company.id }
)

hr_dept = entity_service.create(
  "Human Resources",
  kind: :organization,
  description: "HR team",
  attributes: { parent: company.id }
)

puts "Created company: #{company.name}"
puts "Created departments: #{engineering.name}, #{product.name}, #{hr_dept.name}"

# Create locations
hq = entity_service.create(
  "San Francisco HQ",
  kind: :place,
  aliases: ["SF Office", "Headquarters"],
  attributes: { city: "San Francisco", state: "CA" }
)

remote_office = entity_service.create(
  "Austin Office",
  kind: :place,
  aliases: ["Austin TX Office"],
  attributes: { city: "Austin", state: "TX" }
)

puts "Created locations: #{hq.name}, #{remote_office.name}"

demo_section("Section 2: Create Employee Profiles")

employees = {}

# CEO
employees[:ceo] = entity_service.create(
  "Katherine Rodriguez",
  kind: :person,
  aliases: ["Kate Rodriguez", "K. Rodriguez"],
  attributes: { employee_id: "EMP001", email: "krodriguez@innovatecorp.com" },
  description: "Chief Executive Officer"
)

# VP Engineering
employees[:vp_eng] = entity_service.create(
  "Marcus Chen",
  kind: :person,
  aliases: ["Marc Chen"],
  attributes: { employee_id: "EMP002", email: "mchen@innovatecorp.com" },
  description: "VP of Engineering"
)

# Senior Engineer
employees[:senior_eng] = entity_service.create(
  "Priya Sharma",
  kind: :person,
  attributes: { employee_id: "EMP003", email: "psharma@innovatecorp.com" },
  description: "Senior Software Engineer"
)

# Junior Engineer (will be promoted)
employees[:junior_eng] = entity_service.create(
  "Alex Kim",
  kind: :person,
  attributes: { employee_id: "EMP004", email: "akim@innovatecorp.com" },
  description: "Software Engineer"
)

# Product Manager
employees[:pm] = entity_service.create(
  "Jordan Taylor",
  kind: :person,
  attributes: { employee_id: "EMP005", email: "jtaylor@innovatecorp.com" },
  description: "Product Manager"
)

# HR Manager
employees[:hr_mgr] = entity_service.create(
  "Michelle Brown",
  kind: :person,
  attributes: { employee_id: "EMP006", email: "mbrown@innovatecorp.com" },
  description: "HR Manager"
)

puts "Created #{employees.length} employee profiles"

demo_section("Section 3: Record Initial Employment Facts")

# Ingest an onboarding document
onboarding_doc = source_service.create(
  <<~DOC,
    EMPLOYEE ONBOARDING RECORDS - 2020-2024

    Katherine Rodriguez - Hired as CEO on January 15, 2020
    Marcus Chen - Hired as Engineering Manager on March 1, 2020
    Priya Sharma - Hired as Software Engineer on June 15, 2021
    Alex Kim - Hired as Junior Developer on September 1, 2023
    Jordan Taylor - Hired as Associate PM on February 1, 2022
    Michelle Brown - Hired as HR Coordinator on April 1, 2021
  DOC
  kind: :document,
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
ceo_employment.add_source(source: onboarding_doc, kind: :primary)

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

demo_section("Section 4: Process a Promotion")

# Ingest the promotion memo
promotion_memo = source_service.create(
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
  kind: :document,
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
promoted_fact.add_source(source: promotion_memo, kind: :primary)

puts "Promoted Alex Kim from Junior Developer to Software Engineer"
puts "Previous fact (#{junior_original.id}) now superseded"
puts "New fact ID: #{promoted_fact.id}"

demo_section("Section 5: Record a Transfer")

# Jordan is transferring to Austin
transfer_memo = source_service.create(
  <<~MEMO,
    INTERNAL MEMO
    Date: January 10, 2026
    Subject: Transfer Notice - Jordan Taylor

    Jordan Taylor will be transferring to our Austin office
    effective February 1, 2026. Jordan will continue in the
    Product Manager role but will lead our Texas expansion efforts.
  MEMO
  kind: :document,
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
jordan_austin_location.add_source(source: transfer_memo, kind: :primary)

puts "Recorded Jordan Taylor's transfer to Austin Office"

demo_section("Section 6: Query Employee Information")

# Current state of all employees
puts "\nCurrent Employee Status:"
puts "-" * 50

employees.each do |key, employee|
  puts "\n#{employee.name}:"
  current_facts = fact_service.current_facts(entity: employee.id)
  current_facts.each do |fact|
    puts "  - #{fact.text}"
  end
end

demo_section("Section 7: Historical Query")

# What was Alex Kim's role in December 2024?
puts "\nAlex Kim's facts as of December 2024:"
past_facts = fact_service.facts_at(Date.new(2024, 12, 1), entity: employees[:junior_eng].id)
past_facts.each { |f| puts "  - #{f.text}" }

# What is Alex Kim's role now?
puts "\nAlex Kim's facts as of today:"
current_facts = fact_service.facts_at(Date.today, entity: employees[:junior_eng].id)
current_facts.each { |f| puts "  - #{f.text}" }

demo_section("Section 8: Organization Chart Query")

puts "\nReporting relationships:"
# Find all "reports to" facts
reporting_facts = fact_service.search("reports to")
reporting_facts.each { |f| puts "  #{f.text}" }

puts "\nEngineering Department members:"
engineering_facts = fact_service.current_facts(entity: engineering.id)
engineering_facts.each { |f| puts "  #{f.text}" }

demo_section("Section 9: Employee Timeline")

timeline = fact_service.timeline(
  entity_id: employees[:vp_eng].id,
  from: Date.new(2020, 1, 1),
  to: Date.today
)

timeline.each do |entry|
  end_date = entry[:invalid_at]&.strftime("%Y-%m-%d") || "present"
  status_marker = entry[:status] != "canonical" ? " [#{entry[:status]}]" : ""
  puts "  #{entry[:valid_at].strftime('%Y-%m-%d')} - #{end_date}: #{entry[:text]}#{status_marker}"
end

demo_section("Section 10: Audit Trail")

alex_facts = FactDb::Models::Fact.joins(:entity_mentions)
  .where(entity_mentions: { entity_id: employees[:junior_eng].id })
  .order(:created_at)

puts "Complete fact history:"
alex_facts.each do |fact|
  status_info = fact.status != "canonical" ? " [#{fact.status}]" : ""
  validity = fact.invalid_at ? "#{fact.valid_at} - #{fact.invalid_at}" : "#{fact.valid_at} - present"
  puts "  [#{validity}] #{fact.text}#{status_info}"

  fact.fact_sources.each do |source|
    puts "    Source: #{source.source.title} (#{source.kind})"
  end
end

demo_section("Section 11: Statistics")

puts "Total employees tracked: #{entity_service.by_kind("person").count}"
puts "Total departments: #{entity_service.by_kind("organization").where("description LIKE ?", "%team%").count}"
puts "Total employment facts: #{fact_service.stats[:total]}"
puts "Current facts: #{FactDb::Models::Fact.currently_valid.count}"
puts "Historical facts: #{FactDb::Models::Fact.historical.count}"
puts "Documents processed: #{source_service.stats[:total]}"

demo_footer
