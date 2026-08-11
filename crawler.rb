# frozen_string_literal: true

require 'bundler'
require 'relaton/bipm/data_fetcher'
require_relative 'index_builder'

relaton_ci_pat = ARGV.shift

# Remoeve old files. Match only the generated `index-*` outputs (index-v1.yaml,
# index-v2.yaml, index-v1.zip) — NOT the `index_builder.rb` source this crawler
# requires, which a bare `index*` glob would delete out from under the next run.
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index-*')

# `label:` replaces the command in the failure message, for commands whose text
# embeds a credential (see the metrologia clone below).
def fast_fail_system(command, label: nil, **options)
  unless system(command, **options)
    exit_status = $?.exitstatus || 1 # exit fails if $?.exitstatus is nil
    puts "Command '#{label || command}' failed with exit code #{exit_status}"
    exit exit_status
  end
end

# Clone repositories. These three checkouts are gitignored, so CI always starts
# without them and everything below (metanorma.yml, the site build, the three
# DataFetcher.fetch calls) needs them cloned. Never comment these out: that
# shipped once in 26822298ff and the crawl died 41s in on a missing
# `bipm-si-brochure/metanorma.yml`. The `unless Dir.exist?` guards are what make
# that shortcut unnecessary — a bare re-clone over an existing checkout exits
# 128, so a local rerun reuses the checkout instead of fast-failing. Delete a
# directory to force a fresh clone. spec/crawler_sources_spec.rb guards all this.
fast_fail_system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes') unless Dir.exist?('bipm-data-outcomes')
fast_fail_system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure') unless Dir.exist?('bipm-si-brochure')
# `label:` keeps RELATON_CI_PAT out of the failure message on a failed clone.
unless Dir.exist?('rawdata-bipm-metrologia')
  fast_fail_system("git clone -b 2023-04-23 https://#{relaton_ci_pat}@github.com/relaton/rawdata-bipm-metrologia rawdata-bipm-metrologia",
                   label: 'git clone rawdata-bipm-metrologia')
end

# Workaround: only RXL is consumed downstream by SiBrochureParser. Full-format
# builds (HTML+PDF+XML+RXL) blow past GitHub Actions' 6h job limit, especially
# after a recent mn2pdf/metanorma-bipm slowdown raised per-PDF time from ~30s
# to ~5-10min. Drop a tiny script into the cloned repo that monkey-patches
# Metanorma::Cli::Compiler to force `extensions: rxl`, then runs site generate.
# Remove once metanorma-cli ships a --formats flag (metanorma/metanorma-cli#418).
require 'yaml'
yml_path = 'bipm-si-brochure/metanorma.yml'
yml = YAML.load_file(yml_path)
# Expand collection.yml entries to their child .adoc files. The collection
# render path uses Metanorma::Compile directly (bypassing Cli::Compiler), so
# our monkey-patch doesn't reach it, and it requires presentation.xml output
# for its concatenation step — incompatible with rxl-only. Inlining the
# children sidesteps compile_collections! entirely.
expanded = (yml.dig('metanorma', 'source', 'files') || []).flat_map do |entry|
  next [] if entry.nil?
  next [entry] unless entry.end_with?('.yml', '.yaml')
  coll = YAML.load_file(File.join('bipm-si-brochure', entry))
  coll_dir = File.dirname(entry)
  (coll.dig('manifest', 'docref') || []).map { |d| File.join(coll_dir, d['file']) }
end
yml['metanorma']['source']['files'] = expanded
File.write(yml_path, yml.to_yaml)

File.write('bipm-si-brochure/build_rxl_only.rb', <<~'RUBY')
  require "bundler/setup"
  require "metanorma/cli"

  module Metanorma::Cli
    class Compiler
      orig_init = instance_method(:initialize)
      define_method(:initialize) do |file, options|
        options = (options.is_a?(Hash) ? options : {}).dup
        options[:extensions] ||= "rxl" unless options["extensions"]
        orig_init.bind(self).call(file, options)
      end
    end
  end

  Metanorma::Cli.start(["site", "generate", "--agree-to-terms"])
RUBY

# Generate si-brochure documents (RXL only)
Bundler.with_unbundled_env do
  fast_fail_system('ls', chdir: 'bipm-si-brochure')
  fast_fail_system('bundle update', chdir: 'bipm-si-brochure')
  fast_fail_system('bundle exec ruby build_rxl_only.rb', chdir: 'bipm-si-brochure')
  fast_fail_system('ls', chdir: 'bipm-si-brochure/_site/documents')
end

# Run converters. Each fetch builds the pubid-backed index-v2 for its source,
# populating the pooled :bipm index.
Relaton::Bipm::DataFetcher.fetch 'bipm-data-outcomes'
Relaton::Bipm::DataFetcher.fetch 'bipm-si-brochure'
Relaton::Bipm::DataFetcher.fetch 'rawdata-bipm-metrologia'

# index-v2 (pubid, the runtime index): append the curated static/ docs through
# the same guarded DataFetcher#add_to_index path the fetches use, then save the
# complete pooled index. A new fetcher instance shares the pooled :bipm index.
fetcher = Relaton::Bipm::DataFetcher.new 'data', 'yaml'
BipmIndexBuilder.add_static_to_index_v2 fetcher
fetcher.index.save

# index-v1 (legacy bespoke {group,type,number,year}): rebuilt over every data/ +
# static/ record with the retained Relaton::Bipm::Id parser, for backward-
# compatible consumers still reading the old index format.
BipmIndexBuilder.build_index_v1
