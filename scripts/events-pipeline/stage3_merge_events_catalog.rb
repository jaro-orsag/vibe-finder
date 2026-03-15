#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "date"
require "fileutils"

USAGE = <<~USAGE
  Usage:
    ruby scripts/events-pipeline/stage3_merge_events_catalog.rb <run_id>

  Example:
    ruby scripts/events-pipeline/stage3_merge_events_catalog.rb 2026-03-15_013604
USAGE

if ARGV.length != 1
  warn USAGE
  exit 2
end

run_id = ARGV[0]
unless run_id.match?(/^\d{4}-\d{2}-\d{2}(?:_\d{6})?$/)
  warn "Invalid run_id format: #{run_id.inspect}. Expected YYYY-MM-DD or YYYY-MM-DD_HHMMSS"
  exit 2
end

run_date = run_id[0, 10]
today = Date.parse(run_date)

canonical_path = "data/events/bratislava-events.yaml"
stage2_path = "data/events-pipeline/#{run_id}/2_deduped.yaml"
archive_path = "data/events/archive/bratislava-events_#{run_id}.yaml"
report_path = "data/events-pipeline/#{run_id}/3_merge_report.yaml"

unless File.exist?(canonical_path)
  warn "Missing canonical file: #{canonical_path}"
  exit 1
end

unless File.exist?(stage2_path)
  warn "Missing Stage 2 file: #{stage2_path}"
  exit 1
end

def deep_copy(obj)
  Marshal.load(Marshal.dump(obj))
end

def norm(s)
  s.to_s.downcase.gsub(/[^\p{Alnum}\s]/, " ").gsub(/\s+/, " ").strip
end

def confidence_rank(value)
  case value.to_s
  when "high"
    3
  when "medium"
    2
  when "low"
    1
  else
    0
  end
end

canonical = YAML.load_file(canonical_path)
stage2 = YAML.load_file(stage2_path)

canonical_events = Array(canonical["events"])
stage2_events = Array(stage2["events"])

FileUtils.mkdir_p(File.dirname(archive_path))
FileUtils.cp(canonical_path, archive_path)

active_events = []
archived_past = 0

canonical_events.each do |event|
  event_date = event["date"]
  begin
    parsed_date = Date.parse(event_date.to_s)
  rescue Date::Error
    parsed_date = nil
  end

  if parsed_date && parsed_date < today
    month = parsed_date.strftime("%Y-%m")
    past_archive_path = "data/events/archive/bratislava-events-past_#{month}.yaml"

    past_data = if File.exist?(past_archive_path)
      YAML.load_file(past_archive_path)
    else
      {
        "contract" => canonical["contract"],
        "schema_version" => canonical["schema_version"],
        "last_updated" => run_date,
        "owner_agent" => canonical["owner_agent"],
        "scope" => canonical["scope"],
        "category_taxonomy" => canonical["category_taxonomy"],
        "field_contract" => canonical["field_contract"],
        "required_fields" => canonical["required_fields"],
        "events" => []
      }
    end

    past_events = Array(past_data["events"])
    dedup_key = [norm(event["title"]), event["date"].to_s, norm(event["venue_name"])]
    unless past_events.any? { |e| [norm(e["title"]), e["date"].to_s, norm(e["venue_name"])] == dedup_key }
      past_events << deep_copy(event)
      past_events.sort_by! { |e| [e["date"].to_s, e["title"].to_s] }
      past_data["events"] = past_events
      past_data["last_updated"] = run_date
      File.write(past_archive_path, YAML.dump(past_data))
    end

    archived_past += 1
  else
    active_events << deep_copy(event)
  end
end

index = {}
active_events.each_with_index do |event, i|
  key = [norm(event["title"]), event["date"].to_s, norm(event["venue_name"])]
  index[key] = i
end

added = 0
updated = 0

stage2_events.each do |incoming|
  key = [norm(incoming["title"]), incoming["date"].to_s, norm(incoming["venue_name"])]

  if index.key?(key)
    current = active_events[index[key]]
    changed = false

    if confidence_rank(incoming["confidence"]) > confidence_rank(current["confidence"])
      current["confidence"] = incoming["confidence"]
      changed = true
    end

    if incoming["status"] == "cancelled" && current["status"] != "cancelled"
      current["status"] = "cancelled"
      changed = true
    end

    current_urls = Array(current["source_urls"])
    incoming_urls = Array(incoming["source_urls"])
    merged_urls = (current_urls + incoming_urls).compact.uniq
    if merged_urls != current_urls
      current["source_urls"] = merged_urls
      changed = true
    end

    current_categories = Array(current["categories"])
    incoming_categories = Array(incoming["categories"])
    merged_categories = (current_categories + incoming_categories).compact.uniq
    if merged_categories != current_categories
      current["categories"] = merged_categories
      changed = true
    end

    %w[time_start time_end ticket_url price].each do |field|
      current_blank = current[field].nil? || current[field].to_s.strip.empty?
      incoming_blank = incoming[field].nil? || incoming[field].to_s.strip.empty?
      if current_blank && !incoming_blank
        current[field] = incoming[field]
        changed = true
      end
    end

    incoming_description = incoming["description"].to_s.strip
    current_description = current["description"].to_s.strip
    if !incoming_description.empty? && (current_description.empty? || incoming_description.length > current_description.length)
      current["description"] = incoming["description"]
      changed = true
    end

    updated += 1 if changed
  else
    active_events << deep_copy(incoming)
    index[key] = active_events.length - 1
    added += 1
  end
end

active_events.sort_by! { |e| [e["date"].to_s, e["title"].to_s] }

unchanged = active_events.length - added - updated

canonical["events"] = active_events
canonical["last_updated"] = run_date

File.write(canonical_path, YAML.dump(canonical))

report = {
  "run_id" => run_id,
  "pipeline_stage" => 3,
  "input_count" => stage2_events.length,
  "added" => added,
  "updated" => updated,
  "unchanged" => unchanged,
  "archived_past" => archived_past
}

File.write(report_path, YAML.dump(report))

puts "merge_complete input=#{stage2_events.length} added=#{added} updated=#{updated} unchanged=#{unchanged} archived_past=#{archived_past}"
