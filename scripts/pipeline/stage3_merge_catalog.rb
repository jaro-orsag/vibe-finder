#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "uri"
require "fileutils"
require "set"

USAGE = <<~USAGE
  Usage:
    ruby scripts/pipeline/stage3_merge_catalog.rb <run_id>

  Example:
    ruby scripts/pipeline/stage3_merge_catalog.rb 2026-03-15
    ruby scripts/pipeline/stage3_merge_catalog.rb 2026-03-15_153045
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
canonical_path = "data/sources/bratislava-event-sources.yaml"
stage2_path = "data/pipeline/#{run_id}/2_deduped.yaml"
archive_path = "data/sources/archive/bratislava-event-sources_#{run_id}.yaml"
report_path = "data/pipeline/#{run_id}/3_merge_report.yaml"

def deep_copy(obj)
  Marshal.load(Marshal.dump(obj))
end

def normalize_url(url)
  return nil if url.nil?

  raw = url.to_s.strip
  return nil if raw.empty?

  begin
    uri = URI.parse(raw)
    normalized = if uri.scheme && uri.host
                   path = uri.path.to_s
                   "#{uri.scheme.downcase}://#{uri.host.downcase}#{path}"
                 else
                   raw.downcase
                 end
  rescue URI::InvalidURIError
    normalized = raw.downcase
  end

  normalized = normalized.sub(/[?#].*$/, "")
  normalized = normalized.sub(%r{/+$}, "")
  normalized
end

def source_urls(source)
  urls = [source["homepage_url"]]
  urls.concat(Array(source["event_listing_urls"]))
  urls.map { |u| normalize_url(u) }.compact.uniq
end

def ensure_required_fields(entry, required_fields)
  required_fields.each do |field|
    next if entry.key?(field)

    entry[field] = case field
                   when "event_listing_urls", "languages"
                     []
                   else
                     nil
                   end
  end
end

def confidence_rank(value)
  case value.to_s
  when "high"
    2
  when "medium"
    1
  when "low"
    0
  else
    -1
  end
end

canonical = YAML.load_file(canonical_path)
stage2 = YAML.load_file(stage2_path)

canonical_sources = Array(canonical["sources"])
stage2_sources = Array(stage2["sources"])
required_fields = Array(canonical["required_fields"])

url_to_canonical_index = {}
canonical_sources.each_with_index do |source, index|
  source_urls(source).each do |url|
    url_to_canonical_index[url] ||= index
  end
end

updated_sources = canonical_sources.map { |source| deep_copy(source) }
existing_ids = updated_sources.map { |source| source["id"] }.to_set

catalog_before_count = updated_sources.length
added_ids = []
updated_ids = []

stage2_sources.each do |incoming|
  incoming_urls = source_urls(incoming)
  matched_index = incoming_urls.map { |url| url_to_canonical_index[url] }.compact.first

  if matched_index
    canonical_source = updated_sources[matched_index]
    fields_changed = []

    if confidence_rank(incoming["confidence"]) > confidence_rank(canonical_source["confidence"])
      canonical_source["confidence"] = incoming["confidence"]
      fields_changed << "confidence"
    end

    canonical_event_urls = Array(canonical_source["event_listing_urls"])
    incoming_event_urls = Array(incoming["event_listing_urls"])
    merged_event_urls = (canonical_event_urls + incoming_event_urls).compact.uniq
    if merged_event_urls.length > canonical_event_urls.length
      canonical_source["event_listing_urls"] = merged_event_urls
      fields_changed << "event_listing_urls"
    end

    canonical_genres = Array(canonical_source["genre_tags"])
    incoming_genres = Array(incoming["genre_tags"])
    merged_genres = (canonical_genres + incoming_genres).compact.uniq
    if merged_genres.length > canonical_genres.length
      canonical_source["genre_tags"] = merged_genres
      fields_changed << "genre_tags"
    end

    if canonical_source["homepage_url"].to_s.strip.empty? && !incoming["homepage_url"].to_s.strip.empty?
      canonical_source["homepage_url"] = incoming["homepage_url"]
      fields_changed << "homepage_url"
    end

    %w[name source_type event_focus geo_coverage languages access_type crawl_frequency robots_txt_checked active].each do |field|
      next if incoming[field].nil?
      next unless canonical_source[field].nil? || (canonical_source[field].respond_to?(:empty?) && canonical_source[field].empty?)

      canonical_source[field] = deep_copy(incoming[field])
      fields_changed << field
    end

    if fields_changed.any?
      updated_ids << {
        "id" => canonical_source["id"],
        "fields_changed" => fields_changed.uniq.sort
      }
    end

    source_urls(canonical_source).each do |url|
      url_to_canonical_index[url] ||= matched_index
    end
  else
    new_entry = deep_copy(incoming)
    proposed_id = new_entry["id"].to_s
    final_id = proposed_id

    if existing_ids.include?(final_id)
      suffix = 1
      loop do
        candidate = suffix == 1 ? "#{proposed_id}_new" : "#{proposed_id}_new#{suffix}"
        unless existing_ids.include?(candidate)
          final_id = candidate
          break
        end

        suffix += 1
      end
    end

    new_entry["id"] = final_id
    ensure_required_fields(new_entry, required_fields)

    updated_sources << new_entry
    existing_ids.add(final_id)
    added_ids << final_id

    new_index = updated_sources.length - 1
    source_urls(new_entry).each do |url|
      url_to_canonical_index[url] ||= new_index
    end
  end
end

updated_sources.sort_by! { |source| source["id"].to_s }
canonical["sources"] = updated_sources
canonical["last_updated"] = run_date

FileUtils.mkdir_p(File.dirname(archive_path))
FileUtils.cp(canonical_path, archive_path)
File.write(canonical_path, YAML.dump(canonical))
FileUtils.mkdir_p(File.dirname(report_path))

catalog_after_count = updated_sources.length
updated_count = updated_ids.length
unchanged_count = catalog_before_count - updated_count

report = {
  "run_id" => run_id,
  "run_date" => run_date,
  "catalog_before_count" => catalog_before_count,
  "catalog_after_count" => catalog_after_count,
  "added" => added_ids.length,
  "updated" => updated_count,
  "unchanged" => unchanged_count,
  "archived_to" => archive_path,
  "added_ids" => added_ids,
  "updated_ids" => updated_ids
}

File.write(report_path, YAML.dump(report))

puts "merge_complete before=#{catalog_before_count} after=#{catalog_after_count} added=#{added_ids.length} updated=#{updated_count} unchanged=#{unchanged_count}"