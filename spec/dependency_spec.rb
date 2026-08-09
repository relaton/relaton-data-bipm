# frozen_string_literal: true

require "spec_helper"
require "relaton/bipm"

# Guards the dependency that makes `index-v2` generable at all. The pubid-backed
# index-v2 path (`DataFetcher#index` with `pubid_class: ::Pubid::Bipm::Identifier`
# and `#add_to_index` calling `::Pubid::Bipm.parse`) needs a `pubid` that ships
# the Bipm flavor. The published rubygems `pubid` gem lacks `lib/pubid/bipm.rb`,
# so `Pubid::Bipm` is undefined unless the Gemfile git-pins `metanorma/pubid`.
# Without it the crawl dies with `uninitialized constant Pubid::Bipm` and no
# index-v2 is written — this spec is the regression guard for that pin.
RSpec.describe "Pubid::Bipm availability" do
  it "loads the Pubid::Bipm flavor from the resolved bundle" do
    expect(defined?(Pubid::Bipm)).to eq("constant")
  end

  it "parses a BIPM committee-document id into a Pubid::Bipm identifier" do
    id = Pubid::Bipm.parse("CCTF 14th Meeting (1999)")
    expect(id).to be_a(Pubid::Bipm::Identifier)
  end
end
