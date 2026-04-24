# frozen_string_literal: true

require 'bundler'
require 'relaton_bipm'

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
# Temporary: clone the workaround branch that pins metanorma-standoc to
# the unreleased xref-nil fix (metanorma/metanorma-standoc PR #1175).
# Revert to plain main once metanorma-standoc > 3.4.0 ships on RubyGems.
fast_fail_system('git clone -b temp/use-metanorma-standoc-3.3 https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')
fast_fail_system("git clone -b 2023-04-23 https://#{relaton_ci_pat}@github.com/relaton/rawdata-bipm-metrologia rawdata-bipm-metrologia")

# Generate si-brochure documents
Bundler.with_unbundled_env do
  fast_fail_system('ls', chdir: 'bipm-si-brochure')
  fast_fail_system('bundle update', chdir: 'bipm-si-brochure')
  fast_fail_system('bundle exec metanorma site generate --agree-to-terms', chdir: 'bipm-si-brochure')
  fast_fail_system('ls', chdir: 'bipm-si-brochure/_site/documents')
end

# Run converters
RelatonBipm::DataFetcher.fetch 'bipm-data-outcomes'
RelatonBipm::DataFetcher.fetch 'bipm-si-brochure'
RelatonBipm::DataFetcher.fetch 'rawdata-bipm-metrologia'

index_file = RelatonBipm::BipmBibliography::INDEX_FILE
index = Relaton::Index.find_or_create :bipm, file: index_file
Dir["static/**/*.yaml"].each do |f|
  doc = YAML.load_file f
  id = doc["docid"][0]["id"]
  pubid = RelatonBipm::Id.new.parse id
  index.add_or_update pubid.to_hash, f
end
index.save
