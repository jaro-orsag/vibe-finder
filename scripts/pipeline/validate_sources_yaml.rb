#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

DEFAULT_REQUIRED_FIELDS = %w[
  id
  name
  homepage_url
  event_listing_urls
  source_type
  event_focus
  geo_coverage
  languages
  access_type
  crawl_frequency
  robots_txt_checked
  confidence
  active
].freeze

usage = <<~USAGE
  Usage:
    ruby scripts/pipeline/validate_sources_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]

  Examples:
    ruby scripts/pipeline/validate_sources_yaml.rb data/pipeline/2026-03-15/1_discovered.yaml --stage 1 --date 2026-03-15
    ruby scripts/pipeline/validate_sources_yaml.rb data/sources/bratislava-event-sources.yaml
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

sources = data["sources"]
unless sources.is_a?(Array)
  errors << "missing or non-array 'sources'"
  sources = []
end

required_fields = data["required_fields"]
required_fields = DEFAULT_REQUIRED_FIELDS unless required_fields.is_a?(Array) && !required_fields.empty?

sources.each_with_index do |source, index|
  unless source.is_a?(Hash)
    errors << "source ##{index + 1} is not a mapping"
    next
  end

  missing = required_fields.reject { |field| source.key?(field) }
  next if missing.empty?

  source_id = source["id"] || "index_#{index + 1}"
  errors << "source #{source_id} missing fields: #{missing.join(", ")}"
end

if errors.empty?
  puts "VALID"
  puts "sources=#{sources.length}"
  exit 0
end

warn "INVALID"
errors.each { |err| warn "- #{err}" }
exit 1
