# frozen_string_literal: true

require 'relaton_bipm'

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index.*')

# Clone repositories
system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')

# Generate si-brochure documents
system('cd bipm-si-brochure')
system('bundle install')
system('bundle exec metanorma site generate -c brochure.yml --agree-to-terms')
system('cd ..')

# Run converters
RelatonBipm::DataFetcher.fetch 'bipm-data-outcomes'
RelatonBipm::DataFetcher.fetch 'bipm-si-brochure'

# Zip index
system('zip index.zip index.yaml')

# Stage index
system('git add index.yaml index.zip')
