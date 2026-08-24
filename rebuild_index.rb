#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild index-v2 from the committed data/ and static/ records, with no crawl.
#
# crawler.rb remains the source of truth for data/: it clones the three upstream
# repositories, builds the SI Brochure with metanorma, and writes both indexes.
# That run needs RELATON_CI_PAT and hours of build time, so it is impractical
# outside CI. This script covers the other case - the records are current but
# index-v2 must be rewritten because Pubid::Bipm now serializes its identifiers
# differently.
#
#   bundle exec ruby rebuild_index.rb
#
# It rewrites index-v2.yaml and index-v2.zip, prints the `number` coverage, and
# leaves index-v1 alone: index-v1 is built with the bespoke Relaton::Bipm::Id,
# not with pubid, so a pubid change cannot affect it.

require "zip"
require_relative "index_builder"

INDEX_YAML = "#{Relaton::Bipm::INDEXFILE}.yaml"
INDEX_ZIP = "#{Relaton::Bipm::INDEXFILE}.zip"

BipmIndexBuilder.build_index_v2

# The consumer fetches the zip, not the YAML (Bibliography#index reads
# `#{GH_ENDPOINT}#{INDEXFILE}.zip`). CI zips the index in its own "Diff data"
# step, so a local rebuild has to do it here; keep the flat single-entry layout
# `zip index-v2.zip index-v2.yaml` produces.
File.delete INDEX_ZIP if File.exist? INDEX_ZIP
Zip::File.open(INDEX_ZIP, create: true) { |zip| zip.add INDEX_YAML, INDEX_YAML }

rows = YAML.load_file INDEX_YAML
numberless = rows.select { |r| r[:id]["number"].to_s.empty? }
puts format("%<file>s: %<with>d/%<total>d rows carry a `number`",
            file: INDEX_YAML, with: rows.size - numberless.size, total: rows.size)
rows.group_by { |r| r[:id]["_type"] }.sort.each do |type, group|
  without = group.count { |r| r[:id]["number"].to_s.empty? }
  puts format("  %-32<type>s %5<total>d rows, %5<without>d without", type: type,
                                                                    total: group.size, without: without)
end
puts "rows without a `number`:"
numberless.each { |r| puts "  #{r[:file]}" }
