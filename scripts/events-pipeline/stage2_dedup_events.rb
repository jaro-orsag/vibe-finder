#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

USAGE = <<~USAGE
  Usage:
    ruby scripts/events-pipeline/stage2_dedup_events.rb <run_id> [run_date]

  Example:
    ruby scripts/events-pipeline/stage2_dedup_events.rb 2026-03-15_013604
USAGE

if ARGV.empty? || ARGV.length > 2
  warn USAGE
  exit 2
end

run_id = ARGV[0]
unless run_id.match?(/^\d{4}-\d{2}-\d{2}(?:_\d{6})?$/)
  warn "Invalid run_id format: #{run_id.inspect}. Expected YYYY-MM-DD or YYYY-MM-DD_HHMMSS"
  exit 2
end

run_date = ARGV[1] || run_id[0, 10]
input_path = "data/events-pipeline/#{run_id}/1_crawled.yaml"
out_path = "data/events-pipeline/#{run_id}/2_deduped.yaml"
report_path = "data/events-pipeline/#{run_id}/2_dedup_report.yaml"

unless File.exist?(input_path)
  warn "Missing Stage 1 file: #{input_path}"
  exit 1
end

CONFIDENCE_RANK = { "low" => 1, "medium" => 2, "high" => 3 }.freeze

def normalize(text)
  text.to_s.downcase.gsub(/[^\p{Alnum}\s]/, " ").gsub(/\s+/, " ").strip
end

def blank_value?(value)
  value.nil? || value.to_s.strip.empty?
end

def merge_events(target, incoming)
  if CONFIDENCE_RANK.fetch(incoming["confidence"].to_s, 0) > CONFIDENCE_RANK.fetch(target["confidence"].to_s, 0)
    target["confidence"] = incoming["confidence"]
  end

  target["source_urls"] = (Array(target["source_urls"]) + Array(incoming["source_urls"])).compact.uniq
  target["categories"] = (Array(target["categories"]) + Array(incoming["categories"])).compact.uniq

  %w[time_start time_end ticket_url price].each do |field|
    target[field] = incoming[field] if blank_value?(target[field]) && !blank_value?(incoming[field])
  end

  incoming_description = incoming["description"].to_s.strip
  target_description = target["description"].to_s.strip
  if !incoming_description.empty? && (target_description.empty? || incoming_description.length > target_description.length)
    target["description"] = incoming["description"]
  end
end

data = YAML.load_file(input_path)
events = Array(data["events"])

puts "STAGE2 run_id=#{run_id} input=#{events.length}"

by_key = {}
merges_by_kept = Hash.new { |hash, key| hash[key] = [] }

events.each_with_index do |event, index|
  key = [normalize(event["title"]), event["date"].to_s, normalize(event["venue_name"])]

  if !by_key.key?(key)
    by_key[key] = Marshal.load(Marshal.dump(event))
    puts "STAGE2_EVENT index=#{index + 1}/#{events.length} action=keep id=#{event['id']} output=#{by_key.length}"
    next
  end

  target = by_key[key]
  if CONFIDENCE_RANK.fetch(event["confidence"].to_s, 0) > CONFIDENCE_RANK.fetch(target["confidence"].to_s, 0)
    previous_target_id = target["id"]
    replacement = Marshal.load(Marshal.dump(event))
    merge_events(replacement, target)
    by_key[key] = replacement
    merges_by_kept[replacement["id"]] << previous_target_id unless previous_target_id == replacement["id"]
    target = replacement
  else
    merge_events(target, event)
  end

  merges_by_kept[target["id"]] << event["id"] unless event["id"] == target["id"]
  puts "STAGE2_EVENT index=#{index + 1}/#{events.length} action=merge kept_id=#{target['id']} merged_id=#{event['id']} output=#{by_key.length}"
end

records = by_key.values.map do |event|
  {
    "date" => event["date"].to_s,
    "venue_norm" => normalize(event["venue_name"]),
    "title_norm" => normalize(event["title"]),
    "event" => event
  }
end

records.group_by { |record| [record["date"], record["venue_norm"]] }.each_value do |group|
  next if group.length < 2

  group.combination(2) do |left, right|
    short_title, long_title = [left["title_norm"], right["title_norm"]].sort_by(&:length)
    next if short_title.empty?

    similar = long_title.include?(short_title) && (short_title.length.to_f / long_title.length) >= 0.6
    next unless similar

    left["event"]["confidence"] = "low"
    right["event"]["confidence"] = "low"
  end
end

deduped_events = by_key.values.sort_by { |event| [event["date"].to_s, event["title"].to_s.downcase] }
merged_count = events.length - deduped_events.length

out_doc = {
  "contract" => data["contract"] || "bratislava_events",
  "schema_version" => data["schema_version"] || "1.0.0",
  "pipeline_stage" => 2,
  "run_date" => run_date,
  "events" => deduped_events
}

report_merges = merges_by_kept.keys.sort.map do |kept_id|
  merged_from = merges_by_kept[kept_id].uniq.sort
  next if merged_from.empty?

  {
    "kept_id" => kept_id,
    "merged_from" => merged_from,
    "reason" => "identical title+date+venue"
  }
end.compact

report = {
  "run_id" => run_id,
  "pipeline_stage" => 2,
  "input_count" => events.length,
  "output_count" => deduped_events.length,
  "merged_count" => merged_count,
  "merges" => report_merges
}

File.write(out_path, YAML.dump(out_doc))
File.write(report_path, YAML.dump(report))

puts "STAGE2_DONE input=#{events.length} output=#{deduped_events.length} merged=#{merged_count}"