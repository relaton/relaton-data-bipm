# frozen_string_literal: true

require 'bundler'
require 'relaton/bipm/data_fetcher'

relaton_ci_pat = ARGV.shift

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index*')

def fast_fail_system(command, **options)
  unless system(command, **options)
    exit_status = $?.exitstatus || 1 # exit fails if $?.exitstatus is nil
    puts "Command '#{command}' failed with exit code #{exit_status}"
    exit exit_status
  end
end

# Clone repositories
fast_fail_system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
fast_fail_system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')
fast_fail_system("git clone -b 2023-04-23 https://#{relaton_ci_pat}@github.com/relaton/rawdata-bipm-metrologia rawdata-bipm-metrologia")

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

# Run converters
Relaton::Bipm::DataFetcher.fetch 'bipm-data-outcomes'
Relaton::Bipm::DataFetcher.fetch 'bipm-si-brochure'
Relaton::Bipm::DataFetcher.fetch 'rawdata-bipm-metrologia'

index_file = Relaton::Bipm::INDEXFILE
index = Relaton::Index.find_or_create :bipm, file: index_file
Dir["static/**/*.yaml"].each do |f|
  doc = YAML.load_file f
  id = doc["docidentifier"][0]["content"]
  pubid = Relaton::Bipm::Id.new.parse id
  index.add_or_update pubid.to_hash, f
end
index.save
