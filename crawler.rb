# frozen_string_literal: true

require 'fileutils'
require 'relaton_bipm'

FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index.*')

RelatonBipm::DataFetcher.fetch 'bipm-data-outcomes'
RelatonBipm::DataFetcher.fetch 'bipm-si-brochure'

system("zip index.zip index.yaml")
system("git add index.yaml index.zip")
