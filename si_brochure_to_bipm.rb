#!/usr/bin/env ruby
# frozen_string_literal:true

require 'nokogiri'
require 'fileutils'
require 'relaton_bipm'

dir = 'data'
FileUtils.mkdir_p dir unless File.exist? dir
source_path = File.join ARGV[0], '*.rxl'
index = 'index.yaml'
@index = File.exist?(index) ? YAML.load_file(index) : {}

def deep_merge(hash1, hash2)
  hash1.merge(hash2) do |_key, oldval, newval|
    if oldval.is_a?(Hash) && newval.is_a?(Hash)
      deep_merge(oldval, newval)
    elsif oldval.is_a?(Array) && newval.is_a?(Array)
      oldval | newval
    else
      newval || oldval
    end
  end
end

Dir[source_path].each do |f|
  docstd = Nokogiri::XML File.read f
  doc = docstd.at '/bibdata'
  bibitem = RelatonBipm::XMLParser.from_xml doc.to_xml
  hash1 = bibitem.to_hash
  hash1['docid'].detect { |id| id['type'] == 'BIPM' }['primary'] = true
  outfile = File.join dir, File.basename(f).sub(/(?:-(?:en|fr))?\.rxl$/, '.yaml')
  @index[[hash1['docnumber'] || File.basename(outfile, '.yaml')]] = outfile
  hash = if File.exist? outfile
           hash2 = YAML.load_file outfile
           deep_merge hash1, hash2
         else
           hash1
         end
  File.write outfile, hash.to_yaml, encoding: 'UTF-8'
end

File.write index, @index.to_yaml, encoding: 'UTF-8'
