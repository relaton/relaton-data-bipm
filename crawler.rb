# frozen_string_literal: true

require 'bundler'
require 'relaton_bipm'

relaton_ci_pat = ARGV.shift

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index{-bipm,2,}.*')

# Clone repositories
system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')
system("git clone https://#{relaton_ci_pat}@github.com/relaton/rawdata-bipm-metrologia rawdata-bipm-metrologia")

# Generate si-brochure documents
Bundler.with_unbundled_env do
  system('ls', chdir: 'bipm-si-brochure')
  system('bundle update', chdir: 'bipm-si-brochure')
  system('bundle exec metanorma site generate --agree-to-terms', chdir: 'bipm-si-brochure')
  system('ls', chdir: 'bipm-si-brochure/site/documents')
end

# Run converters
RelatonBipm::DataFetcher.fetch 'bipm-data-outcomes'
RelatonBipm::DataFetcher.fetch 'bipm-si-brochure'
RelatonBipm::DataFetcher.fetch 'rawdata-bipm-metrologia'

# Zip index
system('zip index.zip index.yaml')
system('zip index-bipm.zip index-bipm.yaml')
system('zip index2.zip index2.yaml')

# Stage index
system('git add index.yaml index.zip index-bipm.yaml index-bipm.zip index2.yaml index2.zip')
