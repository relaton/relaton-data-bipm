# frozen_string_literal: true

require 'fileutils'
require 'relaton_bipm'

FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index.*')

system('git clone https://github.com/metanorma/bipm-data-outcomes bipm-data-outcomes')
system('git clone https://github.com/metanorma/bipm-si-brochure bipm-si-brochure')

RelatonBipm::DataFetcher.fetch 'bipm-data-outcomes'
RelatonBipm::DataFetcher.fetch 'bipm-si-brochure'

system('zip index.zip index.yaml')
system('git add index.yaml index.zip')
