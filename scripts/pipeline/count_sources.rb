#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

if ARGV.length != 1
  warn "Usage: ruby scripts/pipeline/count_sources.rb <yaml_file>"
  exit 2
end

file = ARGV[0]

data = YAML.load_file(file)
unless data.is_a?(Hash)
  warn "Invalid YAML root in #{file}: expected mapping"
  exit 1
end

sources = data["sources"]
unless sources.is_a?(Array)
  warn "Invalid #{file}: missing or non-array 'sources'"
  exit 1
end

puts sources.length
