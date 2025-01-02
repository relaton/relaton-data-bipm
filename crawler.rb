# frozen_string_literal: true

require "bundler"
require "relaton_bipm"

# Run converters
# TODO: Move bipm-si-brochure/_site/documents to the right place
# fast_fail_system('ls', chdir: 'bipm-si-brochure/_site/documents')
RelatonBipm::DataFetcher.fetch "bipm-data-outcomes"
RelatonBipm::DataFetcher.fetch "bipm-si-brochure"
RelatonBipm::DataFetcher.fetch "rawdata-bipm-metrologia"

index_file = RelatonBipm::BipmBibliography::INDEX_FILE
index = Relaton::Index.find_or_create :bipm, file: index_file
Dir["static/**/*.yaml"].each do |f|
  doc = YAML.load_file f
  id = doc["docid"][0]["id"]
  pubid = RelatonBipm::Id.new.parse id
  index.add_or_update pubid.to_hash, f
end
index.save
