# frozen_string_literal: true

require "fileutils"
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
  # guarded DataFetcher#add_to_index parses each key with Pubid::Bipm and
  # skips-with-a-warning anything it can't parse. Caller saves the index.
  def add_static_to_index_v2(fetcher, glob = "static/**/*.yaml")
    add_records_to_index_v2 fetcher, Dir[glob].sort
  end

  # Rebuild index-v2 from the committed records alone, with no crawl. The full
  # crawler.rb run needs a credential and hours of metanorma builds, so this is
  # how the index is regenerated after a Pubid::Bipm change that alters the
  # serialized rows (for example the derived `number` that stops 6205 Metrologia
  # rows from sharing the empty binary-search key). It reproduces what the three
  # crawl parsers feed to #add_to_index; see #index_keys for the keying rule and
  # for the one place it is knowingly more permissive than the crawl.
  #
  # @return [Relaton::Index::Type] the saved index
  def build_index_v2(globs: ["data/**/*.yaml", "static/**/*.yaml"])
    file = "#{Relaton::Bipm::INDEXFILE}.yaml"
    # Relaton::Index::Type reads the existing index file lazily and MERGES into
    # it, and Pool#type hands back a pooled index whose rows are already in
    # memory. Drop both, or rows of the previous build survive this one.
    FileUtils.rm_f file
    Relaton::Index.close :bipm
    fetcher = Relaton::Bipm::DataFetcher.new "data", "yaml"
    # One glob at a time, in the given order: add_or_update is last-write-wins
    # on a key collision, and crawler.rb resolves such a collision in favour of
    # the curated static/ doc by appending it after the three fetches. Sorting
    # the globs together would hand that decision to the alphabet instead.
    globs.each { |g| add_records_to_index_v2 fetcher, Dir[g].sort }
    fetcher.index.save
    fetcher.index
  end

  # Add each record in +files+ to the pubid index-v2 held by +fetcher+, warning
  # about a record that yields no key at all (add_to_index warns about the ids
  # it cannot parse, but it never sees a record we found no candidate in).
  def add_records_to_index_v2(fetcher, files)
    files.each do |f|
      doc = YAML.load_file f
      keys = index_keys doc
      if keys.empty?
        warn "index-v2: skipping `#{f}`: no parseable BIPM identifier"
        next
      end
      keys.each { |key| fetcher.add_to_index key, f }
    end
  end

  # The index key(s) of one record, reproducing what the three crawl parsers
  # pass to DataFetcher#add_to_index:
  #
  #   * the `docnumber`, whenever Pubid::Bipm parses it - committee documents
  #     and meetings (DataOutcomesParser#add_to_index). Their `fr` and combined
  #     "en / fr" docidentifiers are deliberately left out: the crawl publishes
  #     one row per document, not one per language, and the `fr` form parses.
  #   * every BIPM docidentifier otherwise. Metrologia records carry no
  #     `docnumber` at all (RawdataBipmMetrologia::Fetcher keys on the primary
  #     docidentifier), and the SI Brochure is indexed once per language file by
  #     SiBrochureParser, which is why the merged data/si-brochure.yaml owns two
  #     rows (E and F) while its own `docnumber` lacks the "BIPM" prefix pubid
  #     needs.
  #
  # The fallback is deliberately one step MORE permissive than the crawl, and
  # the rule is an approximation validated over the whole current data set, not
  # a faithful port. DataOutcomesParser passes the `docnumber` and nothing else,
  # so a committee document whose `docnumber` pubid cannot parse gets no row
  # there, while here a parseable BIPM docidentifier of that same record still
  # would. No record in data/ hits that today - every committee and meeting
  # `docnumber` parses - and the alternative, keying on the directory a record
  # sits in, is more brittle than the extra row is harmful. The row would simply
  # disappear on the next crawl.
  def index_keys(doc)
    docnumber = doc["docnumber"]
    return [docnumber] if parseable?(docnumber)

    (doc["docidentifier"] || []).select { |di| di["type"] == "BIPM" }
      .map { |di| di["content"] }.compact.uniq.select { |c| parseable?(c) }
  end

  # Pubid::Bipm.parse raises a bare RuntimeError on a Parslet failure, and
  # update_codes can raise on a malformed id, so rescue broadly - exactly as
  # the guarded DataFetcher#add_to_index does.
  def parseable?(key)
    return false if key.to_s.empty?

    ::Pubid::Bipm.parse(key)
    true
  rescue StandardError
    false
  end

  # Build the legacy bespoke index-v1 over every data/ and static/ record, keyed
  # on the first candidate of #index_v1_candidates that the bespoke Id grammar
  # accepts. A separate :bipm_v1 index pool keeps these plain hashes out of the
  # pubid-typed :bipm (index-v2) pool.
  def build_index_v1(file: "index-v1.yaml", globs: ["data/**/*.yaml", "static/**/*.yaml"])
    # Start from scratch, as #build_index_v2 does: the pooled :bipm_v1 index and
    # the existing file both carry the rows of an earlier build.
    FileUtils.rm_f file
    Relaton::Index.close :bipm_v1
    index = Relaton::Index.find_or_create :bipm_v1, file: file
    globs.flat_map { |g| Dir[g] }.sort.each do |f|
      doc = YAML.load_file f
      candidates = index_v1_candidates doc
      next if candidates.empty?

      key = index_v1_key candidates
      if key
        index.add_or_update key, f
      else
        warn "index-v1: skipping `#{candidates.first}` (#{f}): no candidate parses"
      end
    end
    index.save
    index
  end

  # The ids to try for one record, in order. The first docidentifier comes
  # first, so every record it already keyed keeps its key. Then every BIPM
  # docidentifier and the docnumber, each also without a leading "BIPM " (as
  # Bibliography.search strips it) - the SI Brochure's first docidentifier is
  # "BIPM SI Brochure sur le SI …", which the Id grammar rejects.
  def index_v1_candidates(doc)
    ids = (doc["docidentifier"] || []).select { |di| di["type"] == "BIPM" }.map { |di| di["content"] }
    ids.unshift doc.dig("docidentifier", 0, "content")
    ids << doc["docnumber"]
    ids.grep(String).flat_map { |id| [id, id.sub(/\ABIPM\s/, "")] }.uniq
  end

  # The bespoke Id hash of the first candidate that parses, or nil.
  def index_v1_key(candidates)
    candidates.each do |id|
      return Relaton::Bipm::Id.new.parse(id).to_hash
    rescue Relaton::RequestError
      next
    end
    nil
  end
end
