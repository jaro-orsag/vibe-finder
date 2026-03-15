#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

REQUIRED_FIELDS = %w[
  id
  title
  date
  venue_name
  venue_city
  categories
  source_urls
  status
  confidence
].freeze

ALLOWED_STATUS = %w[upcoming past cancelled].freeze
ALLOWED_CONFIDENCE = %w[high medium low].freeze
DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/.freeze

usage = <<~USAGE
  Usage:
    ruby scripts/events-pipeline/validate_events_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]

  Examples:
    ruby scripts/events-pipeline/validate_events_yaml.rb data/events-pipeline/2026-03-15_120000/1_crawled.yaml --stage 1 --date 2026-03-15
    ruby scripts/events-pipeline/validate_events_yaml.rb data/events/bratislava-events.yaml
USAGE

if ARGV.empty?
  warn usage
  exit 2
end

file = ARGV.shift
expected_stage = nil
expected_date = nil

until ARGV.empty?
  flag = ARGV.shift
  case flag
  when "--stage"
    expected_stage = Integer(ARGV.shift)
  when "--date"
    expected_date = ARGV.shift
  else
    warn "Unknown flag: #{flag}"
    warn usage
    exit 2
  end
end

begin
  data = YAML.load_file(file)
rescue StandardError => e
  warn "YAML parse error in #{file}: #{e.message}"
  exit 1
end

unless data.is_a?(Hash)
  warn "Invalid YAML root in #{file}: expected mapping"
  exit 1
end

errors = []

if expected_stage && data["pipeline_stage"] != expected_stage
  errors << "pipeline_stage mismatch: expected #{expected_stage}, got #{data["pipeline_stage"].inspect}"
end

if expected_date && data["run_date"].to_s != expected_date
  errors << "run_date mismatch: expected #{expected_date}, got #{data["run_date"].inspect}"
end

events = data["events"]
unless events.is_a?(Array)
  errors << "missing or non-array 'events'"
  events = []
end

events.each_with_index do |event, index|
  unless event.is_a?(Hash)
    errors << "event ##{index + 1} is not a mapping"
    next
  end

  event_id = event["id"] || "index_#{index + 1}"

  missing = REQUIRED_FIELDS.reject { |field| event.key?(field) }
  errors << "event #{event_id} missing fields: #{missing.join(", ")}" unless missing.empty?

  if event.key?("status") && !ALLOWED_STATUS.include?(event["status"])
    errors << "event #{event_id} invalid status: #{event["status"].inspect} (allowed: #{ALLOWED_STATUS.join(", ")})"
  end

  if event.key?("confidence") && !ALLOWED_CONFIDENCE.include?(event["confidence"])
    errors << "event #{event_id} invalid confidence: #{event["confidence"].inspect} (allowed: #{ALLOWED_CONFIDENCE.join(", ")})"
  end

  if event.key?("date") && event["date"].to_s !~ DATE_FORMAT
    errors << "event #{event_id} invalid date format: #{event["date"].inspect} (expected YYYY-MM-DD)"
  end

  if event.key?("categories")
    cats = event["categories"]
    errors << "event #{event_id} categories must be a non-empty list" unless cats.is_a?(Array) && !cats.empty?
  end

  if event.key?("source_urls")
    urls = event["source_urls"]
    errors << "event #{event_id} source_urls must be a non-empty list" unless urls.is_a?(Array) && !urls.empty?
  end
end

if errors.empty?
  puts "VALID"
  puts "events=#{events.length}"
  exit 0
end

warn "INVALID"
errors.each { |err| warn "- #{err}" }
exit 1
