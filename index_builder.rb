# frozen_string_literal: true

require "yaml"
require "relaton/bipm/data_fetcher"

# Builds the two indexes this data repo publishes.
#
#   * index-v2 - the pubid-backed runtime index (rows are Pubid::Bipm
#     identifiers serialized as `_type: pubid:bipm:*`) that the Relaton::Bipm
#     flavor consumes. The three DataFetcher.fetch runs populate the pooled
#     :bipm index for the fetched sources; #add_static_to_index_v2 appends the
#     curated static/ docs through the same guarded DataFetcher#add_to_index.
#
#   * index-v1 - the legacy bespoke {group,type,number,year} hash index. No
#     longer produced or read by the Relaton::Bipm flavor, but still published
#     here for backward-compatible consumers. #build_index_v1 walks every data/
#     and static/ record with the retained Relaton::Bipm::Id parser.
#
# Both builders warn-and-skip an id their parser can't handle (the "not
# supported" CIPM MRA doc, the JCGM orphans now owned by the Jcgm flavor, …)
# rather than aborting the crawl.
module BipmIndexBuilder
  module_function

  # Append the curated static/ docs to the pooled pubid index-v2 held by
  # +fetcher+ (the same index the DataFetcher.fetch runs populated). The
  # guarded DataFetcher#add_to_index parses each docnumber with Pubid::Bipm and
  # skips-with-a-warning anything it can't parse. Caller saves the index.
  def add_static_to_index_v2(fetcher, glob = "static/**/*.yaml")
    Dir[glob].sort.each do |f|
      doc = YAML.load_file f
      fetcher.add_to_index doc["docnumber"], f
    end
  end

  # Build the legacy bespoke index-v1 over every data/ and static/ record. Keyed
  # on the primary docidentifier content (the form the bespoke Id grammar
  # expects), falling back to docnumber. A separate :bipm_v1 index pool keeps
  # these plain hashes out of the pubid-typed :bipm (index-v2) pool.
  def build_index_v1(file: "index-v1.yaml", globs: ["data/**/*.yaml", "static/**/*.yaml"])
    index = Relaton::Index.find_or_create :bipm_v1, file: file
    globs.flat_map { |g| Dir[g] }.sort.each do |f|
      doc = YAML.load_file f
      id = doc.dig("docidentifier", 0, "content") || doc["docnumber"]
      next unless id

      begin
        index.add_or_update Relaton::Bipm::Id.new.parse(id).to_hash, f
      rescue Relaton::RequestError => e
        warn "index-v1: skipping `#{id}` (#{f}): #{e.message}"
      end
    end
    index.save
    index
  end
end
