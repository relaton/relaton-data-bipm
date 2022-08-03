# frozen_string_literal: true

require 'relaton_bipm'

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index.*')

# Clone repositories
system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')

# Generate si-brochure documents
Bundler.with_clean_env do
  system('ls', chdir: 'bipm-si-brochure')
  system('bundle install', chdir: 'bipm-si-brochure')
  system('bundle exec metanorma site generate -c brochure.yml --agree-to-terms', chdir: 'bipm-si-brochure')
end

# Run converters
RelatonBipm::DataFetcher.fetch 'bipm-data-outcomes'
RelatonBipm::DataFetcher.fetch 'bipm-si-brochure'

# Zip index
system('zip index.zip index.yaml')

# Stage index
system('git add index.yaml index.zip')
