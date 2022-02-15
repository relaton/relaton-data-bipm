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
@files = []

def title(content, language)
  { content: content, language: language, script: 'Latn' }
end

def add_part(hash, part)
  id = hash[:docid][0].instance_variable_get(:@id)
  id += "-#{part}"
  id.instance_variable_set(:@id, id)
  hash[:structuredidentifier].instance_variable_set :@part, part
end

def bibitem(**args) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  hash = { title: [], doctype: args[:type] }
  args[:en]['title'] && hash[:title] << title(args[:en]['title'], 'en')
  args[:fr]['title'] && hash[:title] << title(args[:fr]['title'], 'fr')
  hash[:date] = [{ type: 'published', on: args[:en]['date'] }]
  hash[:docid] = [RelatonBib::DocumentIdentifier.new(id: "BIPM #{args[:id]}", type: 'BIPM', primary: true)]
  hash[:link] = [{ type: 'src', content: args[:en]['url'] }]
  hash[:language] = %w[en fr]
  hash[:script] = ['Latn']
  hash[:contributor] = [{
    entity: { url: 'www.bipm.org', name: 'Bureau International des Poids et Mesures', abbreviation: 'BIPM' },
    role: [{ type: 'publisher' }]
  }]
  hash[:structuredidentifier] = RelatonBipm::StructuredIdentifier.new docnumber: args[:num]
  hash
end

Dir[source_path].each do |en_file| # rubocop:disable Metrics/BlockLength
  en = YAML.safe_load_file(en_file, permitted_classes: [Date])['metadata']
  fr_file = en_file.sub 'en', 'fr'
  fr = YAML.safe_load_file(fr_file, permitted_classes: [Date])['metadata']
  # puts "Processing #{en_file}" unless en['title']
  # pref = en['metadata']['title']&.match(/CGPM|CIPM/)&.to_s

  pref = case en_file
         when /cgpm/ then 'CR'
         when /cipm/ then 'PV'
         end
  type = File.basename(en_file).split('.')[0].split('-')[0]
  /^(?<num>\d+)(?:-_(?<part>\d+))?-\d{4}$/ =~ en['url'].split('/').last
  id = "#{pref} #{num}"
  file = "#{id.gsub(' ', '-')}.yaml"
  path = File.join dir, file
  hash = bibitem type: type, en: en, fr: fr, id: id, num: num
  if @files.include?(file) && part
    add_part hash, part
    bib = RelatonBipm::BipmBibliographicItem.new(**hash)
    yaml = YAML.safe_load_file(path, permitted_classes: [Date])
    item = RelatonBipm::BipmBibliographicItem.from_hash(yaml)
    item.relation << RelatonBib::DocumentRelation.new(type: 'partOf', bibitem: bib)
  elsif part
    hash[:title].each { |t| t[:content] = t[:content].sub(/\s\(.+\)$/, '') }
    link = "https://raw.githubusercontent.com/relaton/relaton-data-w3c/main/data/#{file}"
    hash[:link] = [{ type: 'src', content: link }]
    h = bibitem type: type, en: en, fr: fr, id: id, num: num
    add_part h, part
    bib = RelatonBipm::BipmBibliographicItem.new(**h)
    hash[:relation] = [RelatonBib::DocumentRelation.new(type: 'partOf', bibitem: bib)]
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
  else
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
  end
  @files << file
  File.write path, item.to_hash.to_yaml, encoding: 'UTF-8'

  # en['resolutions'].each.with_index do |r, i|
  #   hash = { title: [], doctype: 'resolution' }
  #   r['title'] && hash[:title] << title(r['title'], 'en')
  #   fr_title = fr['resolutions'][i]['title']
  #   fr_title && hash[:title] << title(fr_title, 'fr')
  #   hash[:date] = [{ type: 'published', on: r['dates'].first.to_s }]
  #   num, part = r['identifier'].to_s.split '-'
  #   unless part
  #     part = num
  #     num = en_file.match(/\d+/).to_s
  #   end
  #   pref ||= r['subject'].match(/CGPM|CIPM/).to_s
  #   num = pref + num
  #   id = "#{num}-#{part}"
  #   hash[:docid] = [RelatonBib::DocumentIdentifier.new(id: id, type: 'BIPM', primary: true)]
  #   hash[:link] = [
  #     { type: 'src', content: r['url'] },
  #     { type: 'doi', content: r['reference'] }
  #   ]
  #   hash[:language] = %w[en fr]
  #   hash[:script] = ['Latn']
  #   hash[:contributor] = [{
  #     entity: { url: 'www.bipm.org', name: 'Bureau International des Poids et Mesures', abbreviation: 'BIPM' },
  #     role: [{ type: 'publisher' }]
  #   }]
  #   hash[:structuredidentifier] = RelatonBipm::StructuredIdentifier.new docnumber: num, part: part
  #   item = RelatonBipm::BipmBibliographicItem.new(**hash)
  #   out_file = "#{id}.yaml"
  #   File.write File.join(dir, out_file), item.to_hash.to_yaml, encoding: 'UTF-8'
  # end
end
