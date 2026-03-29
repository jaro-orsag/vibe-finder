#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "set"
require "uri"
require "yaml"

$stdout.sync = true

USAGE = <<~USAGE
  Usage:
    ruby scripts/events-pipeline/stage1_5_crawl_and_dedup_events.rb <run_id> <run_date> [--max-sources N]

  Example:
    ruby scripts/events-pipeline/stage1_5_crawl_and_dedup_events.rb 2026-03-16_100000 2026-03-16
USAGE

if ARGV.length < 2
  warn USAGE
  exit 2
end

run_id = ARGV[0]
run_date_raw = ARGV[1]
opts = ARGV[2..]

unless run_id.match?(/^\d{4}-\d{2}-\d{2}(?:_\d{6})?$/)
  warn "Invalid run_id format: #{run_id.inspect}. Expected YYYY-MM-DD or YYYY-MM-DD_HHMMSS"
  exit 2
end

begin
  run_date = Date.parse(run_date_raw)
rescue ArgumentError
  warn "Invalid run_date: #{run_date_raw.inspect}. Expected YYYY-MM-DD"
  exit 2
end

max_sources = nil
if opts.any?
  if opts.length == 2 && opts[0] == "--max-sources"
    begin
      max_sources = Integer(opts[1])
      raise ArgumentError if max_sources <= 0
    rescue ArgumentError
      warn "Invalid --max-sources value: #{opts[1].inspect}. Must be positive integer"
      exit 2
    end
  else
    warn USAGE
    exit 2
  end
end

ROOT = File.expand_path("../..", __dir__)
SOURCES_FILE = File.join(ROOT, "data/sources/bratislava-event-sources.yaml")
CATEGORIES_FILE = File.join(ROOT, "data/events/categories.yaml")
OUT_DIR = File.join(ROOT, "data/events-pipeline", run_id)
OUT_FILE = File.join(OUT_DIR, "1_5_crawled_deduped.yaml")
REPORT_FILE = File.join(OUT_DIR, "1_5_crawl_report.yaml")

FROM_DATE = run_date
TO_DATE = run_date + 90

SOCIAL_HOST_TOKENS = %w[
  facebook.com
  instagram.com
  tiktok.com
  youtube.com
  youtu.be
  reddit.com
  t.me
  telegram.me
  twitter.com
  x.com
  linkedin.com
].freeze

BLOCKED_BODY_TOKENS = [
  "cloudflare",
  "cf-challenge",
  "captcha",
  "access denied",
  "forbidden",
  "verify you are human",
  "enable javascript",
  "bot protection"
].freeze

USER_AGENTS = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4; rv:124.0) Gecko/20100101 Firefox/124.0"
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
  "maj" => 5,
  "jun" => 6,
  "jul" => 7,
  "oktober" => 10,
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
  "decembra" => 12
}.freeze

STATUS_BLOCKED_CODES = [401, 403, 429, 503].freeze
CONFIDENCE_RANK = { "low" => 1, "medium" => 2, "high" => 3 }.freeze

LINK_HINT_TOKENS = %w[
  event events koncert concert podujatie podujatia program show gig live
  vstupenky tickets calendar kalendar agenda whatson line-up lineup
].freeze

NON_EVENT_LINK_HINT_TOKENS = %w[
  login register privacy cookie terms kontakt contact about kariera career
  newsletter faq support shop merch cart
].freeze

# Class-name fragments used to identify event container elements in HTML.
EVENT_CONTAINER_CLASSES = %w[
  event concert gig show akcia podujatie listing card item entry
  program-item event-item event-card show-item
].freeze

MAX_DETAIL_LINKS_PER_SOURCE = 15


def deep_copy(obj)
  Marshal.load(Marshal.dump(obj))
end


def slugify(text)
  text.to_s
      .downcase
      .tr("áäčďéěíĺľňóôŕřšťúýž", "aacdeeillnoorrstuyz")
      .gsub(/[^a-z0-9]+/, "_")
      .gsub(/\A_+|_+\z/, "")[0, 80]
      .then { |s| s.empty? ? "x" : s }
end


def normalize(text)
  text.to_s.downcase.gsub(/[^\p{Alnum}\s]/, " ").gsub(/\s+/, " ").strip
end


def clean_text(text)
  s = text.to_s.dup
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


def social_source?(source)
  source_type = source["source_type"].to_s.downcase
  return true if source_type.include?("social") || source_type.include?("forum")

  urls = Array(source["event_listing_urls"]) + [source["homepage_url"]]
  urls.compact.any? do |url|
    host = URI.parse(url).host.to_s.downcase
    SOCIAL_HOST_TOKENS.any? { |token| host.include?(token) }
  rescue StandardError
    false
  end
end


def blocked_body?(body)
  t = body.to_s.downcase
  return true if t.empty?

  BLOCKED_BODY_TOKENS.any? { |token| t.include?(token) }
end


# Resolve a potentially relative href string against a base URL.
def resolve_url(href, base_url)
  URI.join(base_url, href.to_s.strip).to_s
rescue StandardError
  nil
end


# Decide whether an anchor looks like an event-detail link based on page content,
# not path templates. Uses anchor text, nearby HTML context and date presence.
def event_link_candidate?(anchor_text:, anchor_html:, href:)
  return false if href.to_s.strip.empty?

  text = anchor_text.to_s.downcase
  html = anchor_html.to_s.downcase
  href_text = href.to_s.downcase
  joined = [text, html, href_text].join(" ")

  return false if NON_EVENT_LINK_HINT_TOKENS.any? { |token| joined.include?(token) }
  return true if LINK_HINT_TOKENS.any? { |token| joined.include?(token) }
  return true unless parse_date_candidates(anchor_text.to_s, from_date: FROM_DATE, to_date: TO_DATE).empty?

  false
end


# Extract links from a page that look like event detail pages.
# Only returns same-host links and relies on semantic cues from anchor/content.
def extract_event_links(html, listing_url, max_links: MAX_DETAIL_LINKS_PER_SOURCE)
  base_uri = URI.parse(listing_url)
  origin   = "#{base_uri.scheme}://#{base_uri.host}"
  seen     = Set.new([listing_url])
  links    = []

  html.to_s.scan(/<a\b[^>]*\bhref=["']([^"'#][^"']*)["'][^>]*>(.*?)<\/a>/im) do |href_match, inner_html|
    break if links.size >= max_links

    absolute = resolve_url(href_match, listing_url)
    next unless absolute&.start_with?(origin)
    next if seen.include?(absolute)

    anchor_text = clean_text(inner_html)
    next unless event_link_candidate?(anchor_text: anchor_text, anchor_html: inner_html, href: absolute)

    seen << absolute
    links << absolute
  end

  links
rescue StandardError
  []
end


def fetch_url(url, referer:, attempt_seed: 0, max_attempts: 3)
  uri = URI.parse(url)
  return [nil, :bad_uri] unless uri.is_a?(URI::HTTP)

  last_status = :error
  attempts = 0

  while attempts < max_attempts
    user_agent = USER_AGENTS[(attempt_seed + attempts) % USER_AGENTS.length]
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = user_agent
    req["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    req["Accept-Language"] = "sk-SK,sk;q=0.95,en-US;q=0.8,en;q=0.7"
    req["Cache-Control"] = "no-cache"
    req["Pragma"] = "no-cache"
    req["Upgrade-Insecure-Requests"] = "1"
    req["Referer"] = referer.to_s unless referer.to_s.empty?

    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 10
      http.read_timeout = 15

      res = http.request(req)
      code = res.code.to_i

      if [301, 302, 303, 307, 308].include?(code) && res["location"]
        redirected = URI.join(url, res["location"]).to_s
        return fetch_url(redirected, referer: referer, attempt_seed: attempt_seed + 1, max_attempts: 2)
      end

      body = res.body.to_s
      body.force_encoding("UTF-8")
      body = body.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
      return [body, code]
    rescue StandardError
      last_status = :error
      attempts += 1
      sleep(0.2 * attempts)
      next
    end
  end

  [nil, last_status]
rescue StandardError
  [nil, :error]
end


def parse_date_candidates(text, from_date:, to_date:)
  parsed = []
  txt = text.to_s

  txt.scan(/\b(\d{4})[-\.\/](\d{1,2})[-\.\/](\d{1,2})\b/) do |y, m, d|
    begin
      date = Date.new(y.to_i, m.to_i, d.to_i)
      parsed << date if date >= from_date && date <= to_date
    rescue StandardError
      next
    end
  end

  txt.scan(/\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b/) do |d, m, y|
    begin
      date = Date.new(y.to_i, m.to_i, d.to_i)
      parsed << date if date >= from_date && date <= to_date
    rescue StandardError
      next
    end
  end

  txt.scan(/\b(\d{1,2})\.(\d{1,2})\.(?!\d)/) do |d, m|
    begin
      year = from_date.year
      date = Date.new(year, m.to_i, d.to_i)
      date = Date.new(year + 1, m.to_i, d.to_i) if date < from_date && (to_date.year > year)
      parsed << date if date >= from_date && date <= to_date
    rescue StandardError
      next
    end
  end

  txt.scan(/\b(\d{1,2})\s+([A-Za-záäčďéíĺľňóôŕšťúýž]+)\s*(\d{4})?/i) do |d, mon, y|
    month = MONTH_TO_NUM[mon.downcase]
    next unless month

    year = y.nil? || y.empty? ? from_date.year : y.to_i
    begin
      date = Date.new(year, month, d.to_i)
      date = Date.new(year + 1, month, d.to_i) if y.to_s.empty? && date < from_date && to_date.year > year
      parsed << date if date >= from_date && date <= to_date
    rescue StandardError
      next
    end
  end

  parsed.uniq
end


def extract_json_ld_blobs(html)
  blobs = []
  html.to_s.scan(/<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/im) do |match|
    blobs << match[0].to_s
  end
  blobs
end


def find_event_objects(node, accumulator)
  case node
  when Hash
    node_type = node["@type"] || node[:@type]
    if node_type
      normalized = Array(node_type).map { |v| v.to_s.downcase }
      accumulator << node if normalized.include?("event")
    end

    if node.key?("@graph")
      find_event_objects(node["@graph"], accumulator)
    else
      node.each_value { |value| find_event_objects(value, accumulator) }
    end
  when Array
    node.each { |item| find_event_objects(item, accumulator) }
  end
end


def category_ids
  @category_ids ||= begin
    raw = YAML.load_file(CATEGORIES_FILE)
    Set.new((raw["categories"] || {}).keys)
  end
end


def categories_for_source(source)
  tags = Array(source["genre_tags"]).map(&:to_s)
  mapped = tags.select { |tag| category_ids.include?(tag) }
  mapped = ["mixed"] if mapped.empty?
  mapped
end


def build_event(source:, source_url:, date_obj:, title:, venue_name:, description:, confidence:)
  cleaned_title = title.to_s.gsub(/\s+/, " ").strip
  cleaned_title = source["name"].to_s if cleaned_title.empty?
  cleaned_venue = venue_name.to_s.strip
  cleaned_venue = source["name"].to_s if cleaned_venue.empty?

  {
    "id" => "evt_#{date_obj.strftime('%Y%m%d')}_#{slugify(cleaned_venue)}_#{slugify(cleaned_title)}",
    "title" => cleaned_title[0, 180],
    "date" => date_obj.strftime("%Y-%m-%d"),
    "venue_name" => cleaned_venue[0, 120],
    "venue_city" => "Bratislava",
    "categories" => categories_for_source(source),
    "source_urls" => [source_url],
    "status" => "upcoming",
    "confidence" => confidence,
    "description" => description.to_s.strip[0, 280]
  }
end


def extract_events_from_json_ld(source:, source_url:, html:)
  events = []

  extract_json_ld_blobs(html).each do |blob|
    parsed = JSON.parse(blob) rescue nil
    next if parsed.nil?

    objects = []
    find_event_objects(parsed, objects)

    objects.each do |obj|
      name = (obj["name"] || obj[:name]).to_s
      start_date_raw = obj["startDate"] || obj[:startDate]
      next if name.strip.empty? || start_date_raw.to_s.strip.empty?

      dates = parse_date_candidates(start_date_raw.to_s, from_date: FROM_DATE, to_date: TO_DATE)
      next if dates.empty?

      location = obj["location"] || obj[:location]
      venue_name = if location.is_a?(Hash)
        location["name"] || location[:name]
      else
        ""
      end

      event_url = obj["url"] || source_url
      description = obj["description"] || obj[:description]

      events << build_event(
        source: source,
        source_url: event_url.to_s.empty? ? source_url : event_url,
        date_obj: dates.first,
        title: name,
        venue_name: venue_name,
        description: description,
        confidence: "high"
      )
    end
  end

  events
end


# Extract the most prominent heading text from an HTML fragment.
def extract_heading_from_block(fragment)
  %w[h1 h2 h3 h4 h5 strong].each do |tag|
    if (m = fragment.match(/<#{tag}\b[^>]*>(.*?)<\/#{tag}>/im))
      heading = clean_text(m[1])
      return heading unless heading.empty?
    end
  end
  # Fall back to the first anchor link text.
  if (m = fragment.match(/<a\b[^>]*>(.*?)<\/a>/im))
    heading = clean_text(m[1])
    return heading unless heading.empty?
  end
  nil
end


# Detect repeating structural blocks that likely represent individual event cards.
# Returns an array of raw HTML fragments — one per candidate event.
def detect_event_blocks(html)
  src                = html.to_s
  class_alternatives = EVENT_CONTAINER_CLASSES.map { |c| Regexp.escape(c) }.join("|")
  blocks             = []

  # Priority 1: <article> tags — semantic and rarely nested.
  src.scan(/<article\b[^>]*>(.*?)<\/article>/im) { |m| blocks << m[0] }
  return blocks if blocks.size >= 3

  # Priority 2 & 3: <li>, <section>, then <div> with event-related class names.
  # Use Regexp#match with an offset to extract content after each opening tag
  # without fighting nested closing tags.
  %w[li section div].each do |tag|
    opening_tag_re = /<#{tag}\b[^>]*class=["'][^"']*(?:#{class_alternatives})[^"']*["'][^>]*>/i
    offset = 0
    while (match = opening_tag_re.match(src, offset))
      blocks << src[match.end(0), 1200].to_s
      offset = match.end(0)
      break if blocks.size >= 60
    end
    return blocks.first(60) if blocks.size >= 3
  end

  blocks.first(60)
end


# Extract candidate events from repeating structural blocks on a listing page.
# Uses heading elements (h1–h5, strong) for titles — more precise than flat text scanning.
# Produces medium-confidence events.
def extract_events_from_blocks(source:, source_url:, html:)
  events = []
  blocks = detect_event_blocks(html)
  return events if blocks.empty?

  blocks.each do |block|
    dates = parse_date_candidates(block, from_date: FROM_DATE, to_date: TO_DATE)
    next if dates.empty?

    title = extract_heading_from_block(block)
    next if title.nil? || title.empty?

    events << build_event(
      source:      source,
      source_url:  source_url,
      date_obj:    dates.first,
      title:       title,
      venue_name:  source["name"].to_s,
      description: "",
      confidence:  "medium"
    )
    break if events.size >= 30
  end

  events
end


def merge_events!(target, incoming)
  target["source_urls"] = (Array(target["source_urls"]) + Array(incoming["source_urls"])).compact.uniq
  target["categories"] = (Array(target["categories"]) + Array(incoming["categories"])).compact.uniq

  if CONFIDENCE_RANK.fetch(incoming["confidence"].to_s, 0) > CONFIDENCE_RANK.fetch(target["confidence"].to_s, 0)
    target["confidence"] = incoming["confidence"]
  end

  incoming_description = incoming["description"].to_s
  target_description = target["description"].to_s
  if target_description.empty? || incoming_description.length > target_description.length
    target["description"] = incoming_description
  end
end


def deduplicate_events(events)
  by_key = {}
  merges = []

  events.each do |event|
    key = [normalize(event["title"]), event["date"].to_s, normalize(event["venue_name"])]

    unless by_key.key?(key)
      by_key[key] = deep_copy(event)
      next
    end

    target = by_key[key]
    merge_events!(target, event)
    merges << {
      "kept_id" => target["id"],
      "merged_id" => event["id"],
      "reason" => "same normalized title+date+venue"
    }
  end

  [by_key.values, merges]
end

sources_doc = YAML.load_file(SOURCES_FILE)
all_sources = Array(sources_doc["sources"])

selected_sources = all_sources.select { |source| source["active"] == true }
selected_sources = selected_sources.reject { |source| social_source?(source) }
selected_sources = selected_sources.first(max_sources) if max_sources

puts "STAGE1_5 run_id=#{run_id} run_date=#{run_date} from=#{FROM_DATE} to=#{TO_DATE} selected_sources=#{selected_sources.length}"

raw_events = []
source_reports = []

selected_sources.each_with_index do |source, index|
  source_id = source["id"].to_s
  source_name = source["name"].to_s

  base_urls = Array(source["event_listing_urls"]).compact.map(&:to_s)
  homepage_url = source["homepage_url"].to_s
  seed_urls = []
  seed_urls << homepage_url unless homepage_url.empty?
  urls_to_try = (base_urls + seed_urls).uniq

  success = false
  blocked = false
  statuses = []
  source_events = 0
  per_source_detail_links = Set.new

  remaining = selected_sources.length - index - 1
  puts "SOURCE_START index=#{index + 1}/#{selected_sources.length} remaining=#{remaining} id=#{source_id} name=#{source_name.inspect} urls=#{urls_to_try.length}"

  urls_to_try.each_with_index do |url, url_index|
    body, status = fetch_url(url, referer: source["homepage_url"].to_s, attempt_seed: index + url_index)
    statuses << status.to_s

    if body.nil?
      blocked ||= STATUS_BLOCKED_CODES.include?(status)
      puts "SOURCE_URL index=#{index + 1}/#{selected_sources.length} url_index=#{url_index + 1}/#{urls_to_try.length} status=#{status} source_events=#{source_events} url=#{url}"
      next
    end

    if STATUS_BLOCKED_CODES.include?(status) || blocked_body?(body)
      blocked = true
      puts "SOURCE_URL index=#{index + 1}/#{selected_sources.length} url_index=#{url_index + 1}/#{urls_to_try.length} status=#{status} blocked=true source_events=#{source_events} url=#{url}"
      next
    end

    success ||= status.to_i >= 200 && status.to_i < 400

    events_here = []
    events_here.concat(extract_events_from_json_ld(source: source, source_url: url, html: body))
    events_here.concat(extract_events_from_blocks(source: source, source_url: url, html: body))

    # Collect event detail links from this listing page for the spider phase.
    per_source_detail_links.merge(extract_event_links(body, url))

    events_here.each do |event|
      raw_events << event
      source_events += 1
    end

    puts "SOURCE_URL index=#{index + 1}/#{selected_sources.length} url_index=#{url_index + 1}/#{urls_to_try.length} status=#{status} found_here=#{events_here.length} source_events=#{source_events} running_raw_events=#{raw_events.length} url=#{url}"

    break if source_events >= 25
  end

  # Spider phase: follow collected event detail links for high-confidence JSON-LD extraction.
  # Detail pages almost always carry structured data that listing pages omit.
  spider_budget = [[MAX_DETAIL_LINKS_PER_SOURCE, 40 - source_events].min, 0].max
  if spider_budget > 0 && per_source_detail_links.any?
    puts "SPIDER_START index=#{index + 1} detail_links=#{per_source_detail_links.size} budget=#{spider_budget} id=#{source_id}"
    per_source_detail_links.first(spider_budget).each_with_index do |detail_url, di|
      sleep(0.3)
      detail_body, detail_status = fetch_url(
        detail_url,
        referer:      source["homepage_url"].to_s,
        attempt_seed: index + di + 50
      )
      next if detail_body.nil? || STATUS_BLOCKED_CODES.include?(detail_status) || blocked_body?(detail_body)

      detail_events = extract_events_from_json_ld(source: source, source_url: detail_url, html: detail_body)
      detail_events.each { |event| raw_events << event; source_events += 1 }
      success ||= detail_status.to_i.between?(200, 399)

      puts "SPIDER_DETAIL index=#{index + 1} di=#{di + 1}/#{[per_source_detail_links.size, spider_budget].min} found=#{detail_events.length} source_events=#{source_events}"
      break if source_events >= 40
    end
  end

  puts "SOURCE_DONE index=#{index + 1}/#{selected_sources.length} remaining=#{remaining} success=#{success} blocked=#{blocked && !success} source_events=#{source_events} id=#{source_id}"

  source_reports << {
    "id" => source_id,
    "name" => source_name,
    "success" => success,
    "blocked" => blocked && !success,
    "statuses" => statuses.uniq,
    "source_events" => source_events
  }
end

deduped_events, merges = deduplicate_events(raw_events)

output = {
  "contract" => "bratislava_events",
  "schema_version" => "1.0.0",
  "pipeline_stage" => "1.5",
  "run_date" => run_date.strftime("%Y-%m-%d"),
  "crawl_report" => {
    "attempted_sources_count" => selected_sources.length,
    "successful_sources_count" => source_reports.count { |r| r["success"] },
    "blocked_sources_count" => source_reports.count { |r| r["blocked"] },
    "raw_events_count" => raw_events.length,
    "deduped_events_count" => deduped_events.length,
    "merged_duplicates_count" => merges.length,
    "ignored_social_sources_count" => all_sources.count { |source| source["active"] == true && social_source?(source) }
  },
  "events" => deduped_events.sort_by { |event| [event["date"].to_s, event["title"].to_s.downcase] }
}

report = {
  "run_id" => run_id,
  "pipeline_stage" => "1.5",
  "from_date" => FROM_DATE.strftime("%Y-%m-%d"),
  "to_date" => TO_DATE.strftime("%Y-%m-%d"),
  "sources" => source_reports,
  "duplicate_merges" => merges
}

FileUtils.mkdir_p(OUT_DIR)
File.write(OUT_FILE, YAML.dump(output))
File.write(REPORT_FILE, YAML.dump(report))

puts "WROTE #{OUT_FILE}"
puts "WROTE #{REPORT_FILE}"
puts "raw_events=#{raw_events.length} deduped_events=#{deduped_events.length} duplicate_merges=#{merges.length}"
