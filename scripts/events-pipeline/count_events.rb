#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

if ARGV.length != 1
  warn "Usage: ruby scripts/events-pipeline/count_events.rb <yaml_file>"
  exit 2
end

file = ARGV[0]

data = YAML.load_file(file)
unless data.is_a?(Hash)
  warn "Invalid YAML root in #{file}: expected mapping"
  exit 1
end

events = data["events"]
unless events.is_a?(Array)
  warn "Invalid #{file}: missing or non-array 'events'"
  exit 1
end

puts events.length
