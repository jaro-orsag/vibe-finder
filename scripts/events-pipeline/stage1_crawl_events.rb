#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "date"
require "uri"
require "net/http"
require "openssl"
require "set"
require "fileutils"

$stdout.sync = true

RUN_ID = ARGV[0]
RUN_DATE = ARGV[1]

if RUN_ID.nil? || RUN_DATE.nil?
  warn "Usage: ruby scripts/events-pipeline/stage1_crawl_events.rb <RUN_ID> <RUN_DATE>"
  exit 2
end

ROOT = File.expand_path("../..", __dir__)
SOURCES_FILE = File.join(ROOT, "data/sources/bratislava-event-sources.yaml")
OUT_DIR = File.join(ROOT, "data/events-pipeline", RUN_ID)
OUT_FILE = File.join(OUT_DIR, "1_crawled.yaml")

FROM_DATE = Date.parse(RUN_DATE)
TO_DATE = FROM_DATE + 90

FALLBACK_PATHS = [
  "/events",
  "/event",
  "/program",
  "/program/",
  "/podujatia",
  "/podujatia/",
  "/kalendar",
  "/kalendar/",
  "/calendar",
  "/calendar/",
  "/news",
  "/aktuality",
  "/culture",
  "/kultura"
].freeze

MONTH_TO_NUM = {
  "january" => 1,
  "february" => 2,
  "march" => 3,
  "april" => 4,
  "may" => 5,
  "june" => 6,
  "july" => 7,
  "august" => 8,
  "september" => 9,
  "october" => 10,
  "november" => 11,
  "december" => 12,
  "januar" => 1,
  "februar" => 2,
  "marec" => 3,
  "april" => 4,
  "maj" => 5,
  "jun" => 6,
  "juli" => 7,
  "august" => 8,
  "september" => 9,
  "oktober" => 10,
  "november" => 11,
  "december" => 12,
  "januara" => 1,
  "februara" => 2,
  "marca" => 3,
  "aprila" => 4,
  "maja" => 5,
  "juna" => 6,
  "jula" => 7,
  "augusta" => 8,
  "septembra" => 9,
  "oktobra" => 10,
  "novembra" => 11,
  "decembra" => 12,
  "januar" => 1,
  "februar" => 2,
  "marec" => 3,
  "april" => 4,
  "maj" => 5,
  "jun" => 6,
  "jul" => 7
}.freeze

def slugify(str)
  ascii = str.to_s
             .downcase
             .tr("áäčďéěíĺľňóôŕřšťúýž", "aacdeeillnoorrstuyz")
             .gsub(/[^a-z0-9]+/, "_")
             .gsub(/\A_+|_+\z/, "")
  ascii.empty? ? "x" : ascii[0, 80]
end

def clean_text(str)
  s = str.to_s.dup
  s.force_encoding("UTF-8")
  s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
  s.gsub!(/<script\b.*?<\/script>/mi, " ")
  s.gsub!(/<style\b.*?<\/style>/mi, " ")
  s.gsub!(/<[^>]+>/, " ")
  s.gsub!(/&nbsp;/i, " ")
  s.gsub!(/&amp;/i, "&")
  s.gsub!(/&quot;/i, '"')
  s.gsub!(/&#39;|&apos;/i, "'")
  s.gsub!(/\s+/, " ")
  s.strip
end

def parse_date_candidates(line)
  dates = []
  txt = line.to_s.dup
  txt.force_encoding("UTF-8")
  txt = txt.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")

  txt.scan(/\b(2026)[\-\.\/](0?[1-9]|1[0-2])[\-\.\/](0?[1-9]|[12]\d|3[01])\b/) do |_y, m, d|
    dates << Date.new(2026, m.to_i, d.to_i) rescue nil
  end

  txt.scan(/\b(0?[1-9]|[12]\d|3[01])\.(0?[1-9]|1[0-2])\.(2026)\b/) do |d, m, _y|
    dates << Date.new(2026, m.to_i, d.to_i) rescue nil
  end

  txt.scan(/\b(0?[1-9]|[12]\d|3[01])\.(0?[1-9]|1[0-2])\.(?!\d)/) do |d, m|
    dates << Date.new(2026, m.to_i, d.to_i) rescue nil
  end

  txt.scan(/\b(0?[1-9]|[12]\d|3[01])\s+([A-Za-záäčďéíĺľňóôŕšťúýž]+)\s+(2026)\b/i) do |d, mon, _y|
    m = MONTH_TO_NUM[mon.downcase]
    dates << Date.new(2026, m, d.to_i) if m
  end

  dates.compact.uniq
end

def in_range?(d)
  d >= FROM_DATE && d <= TO_DATE
end

def fetch_url(url)
  uri = URI.parse(url)
  return [nil, :bad_uri] unless uri.is_a?(URI::HTTP)

  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
  req["Accept"] = "text/html,application/xhtml+xml"

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  http.open_timeout = 10
  http.read_timeout = 12

  res = http.request(req)
  code = res.code.to_i

  if [301, 302, 303, 307, 308].include?(code) && res["location"]
    begin
      redirected = URI.join(url, res["location"]).to_s
      return fetch_url(redirected)
    rescue StandardError
      return [nil, code]
    end
  end

  body = res.body.to_s
  body.force_encoding("UTF-8")
  body = body.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")

  [body, code]
rescue StandardError
  [nil, :error]
end

def blocked_body?(body)
  t = body.to_s.downcase
  return true if t.empty?

  blocked_tokens = [
    "cloudflare", "cf-challenge", "captcha", "access denied", "forbidden",
    "enable javascript", "cookie consent", "before you continue", "bot protection"
  ]
  blocked_tokens.any? { |tok| t.include?(tok) }
end

def discover_fallback_urls(homepage_url)
  uri = URI.parse(homepage_url)
  return [] unless uri.is_a?(URI::HTTP)

  base = "#{uri.scheme}://#{uri.host}"
  FALLBACK_PATHS.map { |p| base + p }
rescue StandardError
  []
end

def previous_stage1_path(root, run_id)
  pattern = File.join(root, "data/events-pipeline/*/1_crawled.yaml")
  candidates = Dir.glob(pattern).reject { |path| path.include?("/#{run_id}/") }
  candidates.max_by { |path| File.mtime(path) }
end

def build_event(date_obj:, source_name:, source_id:, page_url:, line:)
  title = line.gsub(/\s+/, " ").strip
  title = title[0, 140]
  title = "#{source_name} event" if title.empty?

  venue = source_name
  evt_id = "evt_#{date_obj.strftime('%Y%m%d')}_#{slugify(venue)}_#{slugify(title)}"

  {
    "id" => evt_id,
    "title" => title,
    "date" => date_obj.strftime("%Y-%m-%d"),
    "venue_name" => venue,
    "venue_city" => "Bratislava",
    "categories" => ["mixed"],
    "source_urls" => [page_url],
    "status" => "upcoming",
    "confidence" => "low",
    "description" => "Candidate event extracted from source #{source_id}; date/title may require verification."
  }
end

sources = YAML.load_file(SOURCES_FILE)["sources"] || []
active_sources = sources.select { |s| s["active"] == true }
total_sources = active_sources.length
prev_stage1 = previous_stage1_path(ROOT, RUN_ID)

existing_events = []
if prev_stage1 && File.exist?(prev_stage1)
  prev = YAML.load_file(prev_stage1)
  (prev["events"] || []).each do |e|
    begin
      d = Date.parse(e["date"].to_s)
      next unless in_range?(d)

      e_copy = Marshal.load(Marshal.dump(e))
      e_copy["status"] = "upcoming" if d >= FROM_DATE
      existing_events << e_copy
    rescue StandardError
      next
    end
  end
end

attempted = 0
successful = 0
blocked = 0
no_upcoming = 0
blocked_ids = []
successful_ids = []
new_events = []

puts "STAGE1 run_id=#{RUN_ID} run_date=#{RUN_DATE} active_sources=#{total_sources} from=#{FROM_DATE} to=#{TO_DATE}"
puts "SEED previous_stage1=#{prev_stage1 || 'none'} seeded_events=#{existing_events.size}"

active_sources.each_with_index do |source, source_index|
  source_id = source["id"].to_s
  source_name = source["name"].to_s
  listing_urls = Array(source["event_listing_urls"]).compact.map(&:to_s)
  urls_to_try = (listing_urls + discover_fallback_urls(source["homepage_url"].to_s)).uniq
  listing_url_count = listing_urls.uniq.length
  remaining_sources = total_sources - source_index - 1

  attempted += 1
  source_success = false
  source_blocked = false
  source_has_event = false
  source_events_found = 0
  unusable_fallback_streak = 0

  puts "SOURCE_START index=#{source_index + 1}/#{total_sources} remaining=#{remaining_sources} id=#{source_id} name=#{source_name.inspect} urls=#{urls_to_try.length}"

  urls_to_try.each_with_index do |u, url_index|
    is_fallback_url = url_index >= listing_url_count
    body, status = fetch_url(u)

    if body.nil?
      source_blocked = true if status == 403 || status == 429 || status == :error
      unusable_fallback_streak += 1 if is_fallback_url
      puts "SOURCE_URL index=#{source_index + 1}/#{total_sources} url_index=#{url_index + 1}/#{urls_to_try.length} status=#{status} source_events=#{source_events_found} running_new_events=#{new_events.size} url=#{u}"
      if is_fallback_url && unusable_fallback_streak >= 3
        puts "SOURCE_SHORT_CIRCUIT index=#{source_index + 1}/#{total_sources} id=#{source_id} reason=unusable_fallback_streak streak=#{unusable_fallback_streak}"
        break
      end
      next
    end

    if [401, 403, 429, 503].include?(status) || blocked_body?(body)
      source_blocked = true
      unusable_fallback_streak += 1 if is_fallback_url
      puts "SOURCE_URL index=#{source_index + 1}/#{total_sources} url_index=#{url_index + 1}/#{urls_to_try.length} status=#{status} blocked=true source_events=#{source_events_found} running_new_events=#{new_events.size} url=#{u}"
      if is_fallback_url && unusable_fallback_streak >= 3
        puts "SOURCE_SHORT_CIRCUIT index=#{source_index + 1}/#{total_sources} id=#{source_id} reason=unusable_fallback_streak streak=#{unusable_fallback_streak}"
        break
      end
      next
    end

    source_success = true if status >= 200 && status < 400

    text = clean_text(body)
    if text.empty?
      unusable_fallback_streak += 1 if is_fallback_url
      next
    end

    # Use sentence-like chunks to preserve context around detected dates.
    chunks = text.split(/(?<=[\.\!\?])\s+|\s{2,}/).map(&:strip).reject(&:empty?)
    chunks = chunks.first(4000)

    found_for_url = 0
    chunks.each do |chunk|
      next if chunk.length < 8
      next unless chunk =~ /(2026|\d{1,2}\.\d{1,2}\.?)/

      parse_date_candidates(chunk).each do |d|
        next unless in_range?(d)

        new_events << build_event(date_obj: d, source_name: source_name, source_id: source_id, page_url: u, line: chunk)
        source_has_event = true
        found_for_url += 1
        source_events_found += 1
        break if found_for_url >= 15
      end
      break if found_for_url >= 15
    end

    puts "SOURCE_URL index=#{source_index + 1}/#{total_sources} url_index=#{url_index + 1}/#{urls_to_try.length} status=#{status} found_here=#{found_for_url} source_events=#{source_events_found} running_new_events=#{new_events.size} url=#{u}"

    unusable_fallback_streak = 0 if found_for_url.positive?

    if url_index + 1 == listing_url_count && source_events_found.positive?
      puts "SOURCE_SHORT_CIRCUIT index=#{source_index + 1}/#{total_sources} id=#{source_id} reason=listing_urls_found_events source_events=#{source_events_found}"
      break
    end
  end

  if source_success
    successful += 1
    successful_ids << source_id
  end

  if source_blocked && !source_success
    blocked += 1
    blocked_ids << source_id
  end

  no_upcoming += 1 if source_success && !source_has_event

  puts "SOURCE_DONE index=#{source_index + 1}/#{total_sources} remaining=#{remaining_sources} success=#{source_success} blocked=#{source_blocked && !source_success} source_events=#{source_events_found} running_new_events=#{new_events.size} id=#{source_id}"
end

events = existing_events + new_events

FileUtils.mkdir_p(OUT_DIR)

output = {
  "contract" => "bratislava_events",
  "schema_version" => "1.0.0",
  "pipeline_stage" => 1,
  "run_date" => RUN_DATE,
  "crawl_report" => {
    "attempted_sources_count" => attempted,
    "successful_sources_count" => successful,
    "blocked_sources_count" => blocked,
    "no_upcoming_events_count" => no_upcoming,
    "blocked_source_ids" => blocked_ids,
    "successful_source_ids" => successful_ids
  },
  "events" => events
}

File.write(OUT_FILE, YAML.dump(output))
puts "WROTE #{OUT_FILE}"
puts "attempted=#{attempted} successful=#{successful} blocked=#{blocked} no_upcoming=#{no_upcoming}"
puts "events=#{events.size} (existing=#{existing_events.size}, new=#{new_events.size})"
