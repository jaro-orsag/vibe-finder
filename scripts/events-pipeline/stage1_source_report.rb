#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "time"
require "fileutils"

USAGE = <<~USAGE
  Usage:
    ruby scripts/events-pipeline/stage1_source_report.rb <run_id>

  Example:
    ruby scripts/events-pipeline/stage1_source_report.rb 2026-03-15_072200
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

log_path = "data/events-pipeline/#{run_id}/stage1.log"
unless File.exist?(log_path)
  warn "Missing Stage 1 log: #{log_path}"
  exit 1
end

sources_path = "data/sources/bratislava-event-sources.yaml"
source_name_map = {}
if File.exist?(sources_path)
  source_data = YAML.load_file(sources_path)
  Array(source_data["sources"]).each do |source|
    source_name_map[source["id"].to_s] = source["name"].to_s
  end
end

def classify_failure(statuses, blocked_hits)
  return "network_or_fetch_errors" if statuses.include?("error")

  blocked_codes = %w[401 403 429 503]
  return "access_blocked_or_rate_limited" if statuses.any? { |status| blocked_codes.include?(status) }
  return "access_blocked_or_rate_limited" if blocked_hits.positive?

  status_count = statuses.length
  not_found_count = statuses.count("404")
  return "missing_or_invalid_listing_paths" if status_count.positive? && not_found_count.to_f / status_count >= 0.8

  "unknown_unreachable"
end

category_explanations = {
  "network_or_fetch_errors" => "Requests failed before a valid HTTP response was received (connection, DNS, TLS, timeout, or similar transport-level failures).",
  "access_blocked_or_rate_limited" => "Source blocked automated access or required interactive/browser execution (HTTP 401/403/429/503, or blocked-body signals such as anti-bot/captcha pages).",
  "missing_or_invalid_listing_paths" => "Configured listing/fallback URLs mostly returned not found (404), indicating stale paths, moved pages, or incompatible URL structure.",
  "unknown_unreachable" => "Source was unsuccessful but did not match the known failure signatures above; requires manual inspection."
}.freeze

source_stats = Hash.new do |hash, key|
  hash[key] = {
    "id" => key,
    "name" => source_name_map[key],
    "index" => nil,
    "total" => nil,
    "statuses" => [],
    "blocked_hits" => 0,
    "success" => nil,
    "blocked" => nil,
    "source_events" => 0
  }
end

attempted = nil
successful = nil
blocked_total = nil
no_upcoming = nil
events_total = nil
new_events_total = nil
existing_events_total = nil

File.foreach(log_path) do |line|
  line = line.strip

  if (match = line.match(/^SOURCE_START index=(\d+)\/(\d+) remaining=\d+ id=([^\s]+) name="(.*)" urls=\d+$/))
    idx, total, source_id, source_name = match.captures
    source_stats[source_id]["index"] = idx.to_i
    source_stats[source_id]["total"] = total.to_i
    source_stats[source_id]["name"] = source_name
    next
  end

  if (match = line.match(/^SOURCE_URL .* status=([^\s]+)(?: .*|)$/))
    status = match[1]
    if (id_match = line.match(/index=(\d+)\/(\d+)/))
      idx = id_match[1].to_i
      source_id = source_stats.values.find { |s| s["index"] == idx && s["total"] == id_match[2].to_i }&.fetch("id", nil)
      if source_id
        source_stats[source_id]["statuses"] << status
        source_stats[source_id]["blocked_hits"] += 1 if line.include?("blocked=true")
      end
    end
    next
  end

  if (match = line.match(/^SOURCE_DONE index=\d+\/\d+ remaining=\d+ success=(true|false) blocked=(true|false) source_events=(\d+) running_new_events=\d+ id=([^\s]+)$/))
    success_flag, blocked_flag, source_events, source_id = match.captures
    source_stats[source_id]["success"] = success_flag == "true"
    source_stats[source_id]["blocked"] = blocked_flag == "true"
    source_stats[source_id]["source_events"] = source_events.to_i
    next
  end

  if (match = line.match(/^attempted=(\d+) successful=(\d+) blocked=(\d+) no_upcoming=(\d+)$/))
    attempted, successful, blocked_total, no_upcoming = match.captures.map(&:to_i)
    next
  end

  if (match = line.match(/^events=(\d+) \(existing=(\d+), new=(\d+)\)$/))
    events_total, existing_events_total, new_events_total = match.captures.map(&:to_i)
    next
  end
end

sources = source_stats.values.sort_by { |source| source["index"] || 999_999 }
unsuccessful_sources = sources.select { |source| source["success"] == false }

unsuccessful_with_category = unsuccessful_sources.map do |source|
  category = classify_failure(source["statuses"], source["blocked_hits"])
  source.merge("failure_category" => category)
end

failure_categories = unsuccessful_with_category.group_by { |source| source["failure_category"] }
failure_category_counts = failure_categories.transform_values(&:length)

report_data = {
  "run_id" => run_id,
  "generated_at" => Time.now.utc.iso8601,
  "stage1_log" => log_path,
  "totals" => {
    "attempted_sources" => attempted,
    "successful_sources" => successful,
    "unsuccessful_sources" => unsuccessful_sources.length,
    "blocked_sources" => blocked_total,
    "no_upcoming_events_sources" => no_upcoming,
    "events_total" => events_total,
    "seeded_events" => existing_events_total,
    "new_events" => new_events_total
  },
  "events_per_source" => sources.map do |source|
    {
      "index" => source["index"],
      "id" => source["id"],
      "name" => source["name"],
      "events_found" => source["source_events"],
      "success" => source["success"]
    }
  end,
  "unsuccessful_sources" => unsuccessful_with_category.map do |source|
    {
      "index" => source["index"],
      "id" => source["id"],
      "name" => source["name"],
      "failure_category" => source["failure_category"],
      "statuses_seen" => source["statuses"].uniq,
      "blocked_hits" => source["blocked_hits"],
      "events_found" => source["source_events"]
    }
  end,
  "failure_categories" => failure_category_counts.sort_by { |category, _count| category }.to_h,
  "failure_category_explanations" => category_explanations
}

yaml_out = "data/events-pipeline/#{run_id}/stage1_source_report.yaml"
md_out = "data/events-pipeline/#{run_id}/stage1_source_report.md"

File.write(yaml_out, YAML.dump(report_data))

lines = []
lines << "# Stage 1 Source Performance Report"
lines << ""
lines << "Run: #{run_id}"
lines << "Generated at: #{report_data['generated_at']}"
lines << ""
lines << "## Totals"
lines << ""
lines << "- Attempted sources: #{attempted}"
lines << "- Successful sources: #{successful}"
lines << "- Unsuccessful sources: #{unsuccessful_sources.length}"
lines << "- Blocked sources: #{blocked_total}"
lines << "- Successful with no upcoming events: #{no_upcoming}"
lines << "- Stage 1 events total: #{events_total}"
lines << "- Seeded events: #{existing_events_total}"
lines << "- New events: #{new_events_total}"
lines << ""
lines << "## Number of Events per Source"
lines << ""
lines << "| # | Source ID | Source Name | Events Found | Success |"
lines << "|---:|---|---|---:|---|"

sources.each do |source|
  lines << "| #{source['index']} | #{source['id']} | #{source['name']} | #{source['source_events']} | #{source['success']} |"
end

lines << ""
lines << "## Unsuccessful Sources (#{unsuccessful_sources.length})"
lines << ""
lines << "| # | Source ID | Source Name | Failure Category | Statuses Seen |"
lines << "|---:|---|---|---|---|"

unsuccessful_with_category.each do |source|
  statuses = source["statuses"].uniq.join(", ")
  lines << "| #{source['index']} | #{source['id']} | #{source['name']} | #{source['failure_category']} | #{statuses} |"
end

lines << ""
lines << "## Failure Categories"
lines << ""
lines << "| Category | Sources |"
lines << "|---|---:|"

failure_category_counts.sort_by { |_category, count| -count }.each do |category, count|
  lines << "| #{category} | #{count} |"
end

lines << ""
lines << "## Failure Category Explanations"
lines << ""

failure_category_counts.sort_by { |_category, count| -count }.each do |category, _count|
  lines << "- #{category}: #{category_explanations[category]}"
end

File.write(md_out, lines.join("\n") + "\n")

puts "WROTE #{yaml_out}"
puts "WROTE #{md_out}"
puts "unsuccessful_sources=#{unsuccessful_sources.length}"