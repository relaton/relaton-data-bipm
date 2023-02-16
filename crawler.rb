# frozen_string_literal: true

require 'bundler'
require 'relaton_bipm'

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index.*')

# Clone repositories
system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')
system('git clone https://github.com/relaton/rawdata-bipm-metrologia rawdata-bipm-metrologia')

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

# Stage index
system('git add index.yaml index.zip')
