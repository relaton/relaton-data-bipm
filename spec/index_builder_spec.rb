# frozen_string_literal: true

require "spec_helper"

# Behaviour of the dual-index builders the crawler uses. These exercise the
# real migrated Relaton::Bipm stack (pubid index-v2 + bespoke index-v1) without
# the crawler's network clones.
RSpec.describe BipmIndexBuilder do
  # A committee doc whose bespoke docidentifier parses on BOTH the pubid grammar
  # and the legacy Relaton::Bipm::Id parser.
  let(:cctf) do
    { "docnumber" => "CCTF 14th Meeting (1999)",
      "docidentifier" => [{ "content" => "CCTF 14th Meeting (1999)" }] }
  end
  # The "not supported" CIPM MRA doc: pubid parses it (MRA rule + update_codes on
  # the (REV) docnumber); the legacy Id parser cannot.
  let(:cipm) do
    { "docnumber" => "CIPM/2005-06(REV)",
      "docidentifier" => [{ "content" => "CIPM 2005-06" }] }
  end
  # A JCGM orphan: owned by the Jcgm flavor now, unparseable by BIPM either way.
  let(:jcgm) do
    { "docnumber" => "JCGM 100:2008",
      "docidentifier" => [{ "content" => "JCGM 100:2008" }] }
  end

  describe ".build_index_v1" do
    it "indexes bespoke {group,type,number,year} rows and skips unparseable ids" do
      in_workdir("data/cctf/meeting/14.yaml" => cctf,
                 "static/cipm/2005-06.yaml" => cipm,
                 "static/jcgm/100-2008.yaml" => jcgm) do
        expect { described_class.build_index_v1 }.not_to raise_error
        rows = YAML.load_file("index-v1.yaml")
        expect(rows.size).to eq(1)
        expect(rows.first[:id]).to eq(group: "CCTF", type: "Meeting", number: "14", year: "1999")
        expect(rows.first[:file]).to eq("data/cctf/meeting/14.yaml")
      end
    end
  end

  describe ".add_static_to_index_v2" do
    it "indexes parseable static docs as pubid rows and skips orphans without raising" do
      in_workdir("static/cipm/2005-06.yaml" => cipm,
                 "static/jcgm/100-2008.yaml" => jcgm) do
        fetcher = Relaton::Bipm::DataFetcher.new("data", "yaml")
        expect { described_class.add_static_to_index_v2(fetcher) }.not_to raise_error
        fetcher.index.save
        rows = YAML.load_file("#{Relaton::Bipm::INDEXFILE}.yaml")
        files = rows.map { |r| r[:file] }
        expect(files).to include("static/cipm/2005-06.yaml")
        expect(files).not_to include("static/jcgm/100-2008.yaml")
        expect(rows.find { |r| r[:file] == "static/cipm/2005-06.yaml" }[:id])
          .to include("_type" => "pubid:bipm:committee-document")
      end
    end
  end
end
