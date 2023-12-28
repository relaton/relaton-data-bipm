# frozen_string_literal: true

require 'bundler'
require 'relaton_bipm'

relaton_ci_pat = ARGV.shift

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index*')

def fast_fail_system(command)
  unless system(command)
    puts "Command '#{command}' failed with exit code #{$?.exitstatus}"
    exit $?.exitstatus
  end
end

# Clone repositories
fast_fail_system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
fast_fail_system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')
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
  pubid = RelatonBipm::Id.new id
  index.add_or_update pubid.to_hash, f
end
index.save
