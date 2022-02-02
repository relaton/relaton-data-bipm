#!/usr/bin/env ruby
# frozen_string_literal:true

##
# Converts BIPM resolutions from https://github.com/metanorma/cipm-resolutions
# and https://github.com/metanorma/cgpm-resolutions to Relaton YAML format.
#
# Usage:
# $ ./res_to_bipm.rb DIR
#
# DIR is a path to EN version of source files directory.
#
# Example:
# $ ./res_to_bipm.rb ../cgpm-resolutions/meetings-en
#
# Output directory is `./data`
#

require 'yaml'
require 'date'
require 'fileutils'
require 'relaton_bipm'

dir = 'data'
FileUtils.mkdir_p dir unless File.exist? dir
source_path = File.join ARGV[0], '*.{yml,yaml}'

def title(content, language)
  { content: content, language: language, script: 'Latn' }
end

Dir[source_path].each do |en_file|
  en = YAML.load_file en_file, permitted_classes: [Date]
  fr_file = en_file.sub 'en', 'fr'
  fr = YAML.load_file fr_file, permitted_classes: [Date]
  puts "Processing #{en_file}" unless en['metadata']['title']
  pref = en['metadata']['title']&.match(/CGPM|CIPM/)&.to_s

  en['resolutions'].each.with_index do |r, i|
    hash = { title: [], doctype: 'resolution' }
    r['title'] && hash[:title] << title(r['title'], 'en')
    fr_title = fr['resolutions'][i]['title']
    fr_title && hash[:title] << title(fr_title, 'fr')
    hash[:date] = [{ type: 'published', on: r['dates'].first.to_s }]
    num, part = r['identifier'].to_s.split '-'
    unless part
      part = num
      num = en_file.match(/\d+/).to_s
    end
    pref ||= r['subject'].match(/CGPM|CIPM/).to_s
    num = pref + num
    id = "#{num}-#{part}"
    hash[:docid] = [RelatonBib::DocumentIdentifier.new(id: id, type: 'BIPM', primary: true)]
    hash[:link] = [
      { type: 'src', content: r['url'] },
      { type: 'doi', content: r['reference'] }
    ]
    hash[:language] = %w[en fr]
    hash[:script] = ['Latn']
    hash[:contributor] = [{
      entity: { url: 'www.bipm.org', name: 'Bureau Intrnational des Poids et Mesures', abbreviation: 'BIPM' },
      role: [{ type: 'publisher' }]
    }]
    hash[:structuredidentifier] = RelatonBipm::StructuredIdentifier.new docnumber: num, part: part
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
    out_file = "#{id}.yaml"
    File.write File.join(dir, out_file), item.to_hash.to_yaml, encoding: 'UTF-8'
  end
end
