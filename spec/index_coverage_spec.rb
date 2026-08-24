# frozen_string_literal: true

require "spec_helper"

# Guards the published `index-v2.yaml` artifact itself.
#
# `Relaton::Index::Type` narrows a lookup by binary-searching the index on
# `id.root.number.to_s` (`bsearch_left` / `bsearch_right`), so every row whose
# identifier has no `number` keys to `""` and lands in one bucket, degenerating
# the search into a linear scan. Before the `metanorma/pubid` BIPM `number`
# change, 6213 of 7922 rows shared that empty key.
#
# Exactly seven rows are number-less BY DESIGN and must stay so: the six
# ordinal-less committee declarations (`data/**/[year]-00.yaml`), whose empty
# number segment is documented in their URN (`urn:bipm:cgpm:decl::1889`), and
# the journal-level `data/metrologia.yaml` record, which carries no volume.
# Any other number-less row means a pubid family was missed, or that the index
# was regenerated with a pubid that predates the change.
RSpec.describe "index-v2 coverage" do
  # Absolute: other specs chdir into throwaway working directories.
  REPO_ROOT = File.expand_path("..", __dir__)
  INDEX_V2 = File.join(REPO_ROOT, "#{Relaton::Bipm::INDEXFILE}.yaml")

  # The ordinal-less declarations plus the journal-level Metrologia record.
  NUMBERLESS_BY_DESIGN = %w[
    data/cgpm/meeting/statement/1889-00.yaml
    data/cipm/meeting/recommendation/1961-00.yaml
    data/cipm/meeting/resolution/1879-00.yaml
    data/cipm/meeting/resolution/1948-00.yaml
    data/cipm/meeting/statement/1964-00.yaml
    data/cipm/meeting/statement/2001-00.yaml
    data/metrologia.yaml
  ].freeze

  let(:rows) { YAML.load_file(INDEX_V2) }
  let(:records) do
    Dir[File.join(REPO_ROOT, "data/**/*.yaml"), File.join(REPO_ROOT, "static/**/*.yaml")]
      .map { |f| f.delete_prefix("#{REPO_ROOT}/") }
  end

  it "leaves only the seven by-design rows without a `number`" do
    numberless = rows.select { |r| r[:id]["number"].to_s.empty? }
    expect(numberless.map { |r| r[:file] }).to contain_exactly(*NUMBERLESS_BY_DESIGN)
  end

  it "indexes every record under data/ and static/, and nothing else" do
    expect(rows.map { |r| r[:file] }.uniq).to match_array(records)
  end
end
