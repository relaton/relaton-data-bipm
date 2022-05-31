#!/usr/bin/env ruby
# frozen_string_literal:true

##
# Converts BIPM resolutions from https://github.com/metanorma/bipm-data-outcomes,
# https://github.com/metanorma/cipm-resolutions, and
# https://github.com/metanorma/cgpm-resolutions to Relaton YAML format.
#
# Usage:
# $ ./res_to_bipm.rb DIR
#
# DIR is a path to dir with bipm-data-outcomes repository.
#
# Example:
# $ ./res_to_bipm.rb ../
#
# Output directory is `./data`
#

require 'yaml'
require 'date'
require 'fileutils'
require 'relaton_bipm'

@output_dir = 'data'
FileUtils.mkdir_p @output_dir unless File.exist? @output_dir
source_path = File.join ARGV[0], 'bipm-data-outcomes', '{cctf,cgpm,cipm}' # '*.{yml,yaml}'
@files = []

def title(content, language)
  { content: content, language: language, script: 'Latn' }
end

#
# Add part to ID and structured identifier
#
# @param [Hash] hash Hash of BIPM meeting
# @param [String] session number of meeting
#
def add_part(hash, part)
  id = hash[:docid][0].instance_variable_get(:@id)
  id += "-#{part}"
  hash[:docid][0].instance_variable_set(:@id, id)
  hash[:structuredidentifier].instance_variable_set :@part, part
end

#
# Create hash from BIPM meeting/resolution
#
# @param [Hash] **args Hash of arguments
# @option args [String] :type Type of meeting/resolution
# @option args [Hash] :en Hash of English metadata
# @option args [Hash] :fr Hash of French metadata
# @option args [String] :id ID of meeting/resolution
# @option args [String] :num Number of meeting/resolution
#
# @return [Hash] Hash of BIPM meeting/resolution
#
def bibitem(**args) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  hash = { title: [], doctype: args[:type] }
  args[:en]['title'] && hash[:title] << title(args[:en]['title'], 'en')
  args[:fr]['title'] && hash[:title] << title(args[:fr]['title'], 'fr')
  hash[:date] = [{ type: 'published', on: args[:en]['date'] }]
  hash[:docid] = [RelatonBib::DocumentIdentifier.new(id: args[:id], type: 'BIPM', primary: true)]
  hash[:id] = args[:id].gsub ' ', '-'
  hash[:docnumber] = args[:id]
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

def write_file(path, item, warn_duplicate: true)
  if @files.include?(path)
    warn "File #{path} already exists" if warn_duplicate
  else
    @files << path
  end
  File.write path, item.to_hash.to_yaml, encoding: 'UTF-8'
end

#
# Parse year from date
#
# @param [Hash] metadata Hash of metadata
#
# @return [String] Year
#
def year(metadata)
  metadata['date'].split('-').first
end

def fetch_resolution(body, eng, frn, dir) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  eng['resolutions'].each.with_index do |r, i| # rubocop:disable Metrics/BlockLength
    hash = { title: [], doctype: r['type'] }
    r['title'] && hash[:title] << title(r['title'], 'en')
    fr_title = frn['resolutions'][i]['title']
    fr_title && hash[:title] << title(fr_title, 'fr')
    date = r['dates'].first.to_s
    hash[:date] = [{ type: 'published', on: date }]
    num = r['identifier'].to_s.split('-').last
    year = date.split('-').first
    num = '0' if num == year
    type = r['type'].capitalize
    id = "#{body} #{type}"
    hash[:id] = "#{body}-#{type}-#{year}"
    if num.to_i.positive?
      id += " #{num}"
      hash[:id] += "-#{num}"
    end
    id += " (#{year})"
    hash[:docid] = [RelatonBib::DocumentIdentifier.new(id: id, type: 'BIPM', primary: true)]
    hash[:docnumber] = id
    hash[:link] = [
      { type: 'src', content: r['url'] },
      { type: 'doi', content: r['reference'] }
    ]
    hash[:language] = %w[en fr]
    hash[:script] = ['Latn']
    hash[:contributor] = [{
      entity: { url: 'www.bipm.org', name: 'Bureau International des Poids et Mesures', abbreviation: 'BIPM' },
      role: [{ type: 'publisher' }]
    }]
    hash[:structuredidentifier] = RelatonBipm::StructuredIdentifier.new docnumber: num
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
    file = year
    file += "-#{num.rjust(2, '0')}" if num.size < 4
    file += '.yaml'
    out_dir = File.join dir, r['type'].downcase
    Dir.mkdir out_dir unless Dir.exist? out_dir
    path = File.join out_dir, file
    write_file path, item
  end
end

#
# Create and write BIPM meeting/resolution
#
# @param [String] en_file Path to English file
# @param [String] body Body name
# @param [String] type Type of Recommendation/Decision/Resolution
# @param [String] dir output directory
#
def fetch_meeting(en_file, body, type, dir) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  en = YAML.safe_load_file(en_file, permitted_classes: [Date])
  en_md = en['metadata']
  fr_file = en_file.sub 'en', 'fr'
  fr = YAML.safe_load_file(fr_file, permitted_classes: [Date])
  fr_md = fr['metadata']

  /^(?<num>\d+)(?:-_(?<part>\d+))?-\d{4}$/ =~ en_md['url'].split('/').last
  # tp = 'Meeting'
  id = "#{body} #{type.capitalize} #{num}"
  file = "#{num}.yaml"
  path = File.join dir, file
  hash = bibitem type: type, en: en_md, fr: fr_md, id: id, num: num
  if @files.include?(path) && part
    add_part hash, part
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
    yaml = YAML.safe_load_file(path, permitted_classes: [Date])
    has_part_item = RelatonBipm::BipmBibliographicItem.from_hash(yaml)
    has_part_item.relation << RelatonBib::DocumentRelation.new(type: 'partOf', bibitem: item)
    write_file path, has_part_item, warn_duplicate: false
    path = File.join dir, "#{num}-#{part}.yaml"
  elsif part
    hash[:title].each { |t| t[:content] = t[:content].sub(/\s\(.+\)$/, '') }
    link = "https://raw.githubusercontent.com/relaton/relaton-data-w3c/main/#{path}"
    hash[:link] = [{ type: 'src', content: link }]
    h = bibitem type: type, en: en_md, fr: fr_md, id: "#{id}-#{part}", num: num
    part_item = RelatonBipm::BipmBibliographicItem.new(**h)
    part_item_path = File.join dir, "#{num}-#{part}.yaml"
    write_file part_item_path, part_item
    hash[:relation] = [RelatonBib::DocumentRelation.new(type: 'partOf', bibitem: part_item)]
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
  else
    item = RelatonBipm::BipmBibliographicItem.new(**hash)
  end
  write_file path, item
  fetch_resolution body, en, fr, dir
end

def fetch_type(dir, body)
  type = dir.split('/').last.split('-').first
  body_dir = File.join @output_dir, body.downcase
  Dir.mkdir body_dir unless Dir.exist? body_dir
  outdir = File.join body_dir, type.downcase
  Dir.mkdir outdir unless Dir.exist? outdir
  Dir[File.join(dir, '*.{yml,yaml}')].each { |en_file| fetch_meeting en_file, body, type, outdir }
end

def fetch_body(dir)
  body = dir.split('/').last.upcase
  Dir[File.join(dir, '*-en')].each { |type_dir| fetch_type type_dir, body }
end

Dir[source_path].each { |body_dir| fetch_body(body_dir) }
