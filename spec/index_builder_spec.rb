# frozen_string_literal: true

require "spec_helper"

# Behaviour of the dual-index builders the crawler uses. These exercise the
# real migrated Relaton::Bipm stack (pubid index-v2 + bespoke index-v1) without
# the crawler's network clones.
RSpec.describe BipmIndexBuilder do
  # A committee doc whose bespoke docidentifier parses on BOTH the pubid grammar
  # and the legacy Relaton::Bipm::Id parser. Carries the real three-entry
  # docidentifier shape of `data/cctf/meeting/14.yaml`: en, fr and the combined
  # "en / fr" form, all `type: BIPM` and all `primary`.
  let(:cctf) do
    { "docnumber" => "CCTF 14th Meeting (1999)",
      "docidentifier" => [
        { "language" => "en", "content" => "CCTF 14th Meeting (1999)", "type" => "BIPM", "primary" => true },
        { "language" => "fr", "content" => "CCTF 14<sup>e</sup> réunion (1999)", "type" => "BIPM", "primary" => true },
        { "content" => "CCTF 14th Meeting (1999) / CCTF 14<sup>e</sup> réunion (1999)", "type" => "BIPM", "primary" => true },
      ] }
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
  # A Metrologia article: no `docnumber` at all, so the primary docidentifier is
  # the only key available.
  let(:metrologia) do
    { "docidentifier" => [
      { "content" => "Metrologia 1 1 1", "type" => "BIPM", "primary" => true },
      { "content" => "10.1088/0026-1394/1/1/001", "type" => "doi" },
    ] }
  end
  # The SI Brochure: one merged record whose `docnumber` pubid rejects (no
  # "BIPM" prefix) and which carries one BIPM docidentifier per language.
  let(:si_brochure) do
    { "docnumber" => "SI Brochure 9e v3.01 (2019/2024, E)",
      "docidentifier" => [
        { "content" => "BIPM SI Brochure sur le SI 9e v3.01 (2019/2024, F)", "type" => "BIPM", "primary" => true },
        { "content" => "978-92-822-2272-0", "type" => "ISBN" },
        { "content" => "BIPM SI Brochure 9e v3.01 (2019/2024, E)", "type" => "BIPM", "primary" => true },
      ] }
  end

  def index_v2_rows
    YAML.load_file("#{Relaton::Bipm::INDEXFILE}.yaml")
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
        rows = index_v2_rows
        files = rows.map { |r| r[:file] }
        expect(files).to include("static/cipm/2005-06.yaml")
        expect(files).not_to include("static/jcgm/100-2008.yaml")
        expect(rows.find { |r| r[:file] == "static/cipm/2005-06.yaml" }[:id])
          .to include("_type" => "pubid:bipm:committee-document")
      end
    end
  end

  # The offline rebuild: index-v2 rebuilt from the committed `data/` + `static/`
  # records alone, with no crawl. Every example pins one half of the keying rule
  # that reproduces what the three crawl parsers feed to `#add_to_index`.
  describe ".build_index_v2" do
    it "keys a committee document off its docnumber, not off every BIPM docidentifier" do
      in_workdir("data/cctf/meeting/14.yaml" => cctf) do
        described_class.build_index_v2
        rows = index_v2_rows
        # The fr id parses too ("CCTF 14e réunion (1999)"), so a naive
        # all-docidentifiers rule would publish a second, language-F row.
        expect(rows.size).to eq(1)
        expect(rows.first[:id])
          .to include("_type" => "pubid:bipm:meeting", "group" => "CCTF", "number" => "14")
        expect(rows.first[:id]).not_to include("language")
        expect(rows.first[:file]).to eq("data/cctf/meeting/14.yaml")
      end
    end

    it "keys a Metrologia article off its primary docidentifier, having no docnumber" do
      in_workdir("data/metrologia-1-1-1.yaml" => metrologia) do
        described_class.build_index_v2
        rows = index_v2_rows
        expect(rows.size).to eq(1)
        expect(rows.first[:id]).to include("_type" => "pubid:bipm:metrologia-article", "volume" => 1)
        expect(rows.first[:file]).to eq("data/metrologia-1-1-1.yaml")
      end
    end

    it "gives the SI Brochure one row per language, its docnumber being unparseable" do
      in_workdir("data/si-brochure.yaml" => si_brochure) do
        described_class.build_index_v2
        rows = index_v2_rows
        expect(rows.size).to eq(2)
        expect(rows.map { |r| r[:id]["language"] }).to contain_exactly("E", "F")
        expect(rows.map { |r| r[:file] }.uniq).to eq(["data/si-brochure.yaml"])
      end
    end

    it "skips a record with no parseable BIPM identifier without raising" do
      in_workdir("data/cctf/meeting/14.yaml" => cctf,
                 "static/jcgm/100-2008.yaml" => jcgm) do
        expect { described_class.build_index_v2 }.not_to raise_error
        expect(index_v2_rows.map { |r| r[:file] }).to eq(["data/cctf/meeting/14.yaml"])
      end
    end

    # Pins the documented deviation from DataOutcomesParser, which passes the
    # `docnumber` alone and so drops such a record. Here a parseable BIPM
    # docidentifier still carries it into the index.
    it "falls back to a BIPM docidentifier when the docnumber is unparseable" do
      broken = { "docnumber" => "CCTF Meeting no. 14, 1999",
                 "docidentifier" => [{ "content" => "CCTF 14th Meeting (1999)", "type" => "BIPM",
                                       "primary" => true }] }
      in_workdir("data/cctf/meeting/14.yaml" => broken) do
        described_class.build_index_v2
        rows = index_v2_rows
        expect(rows.size).to eq(1)
        expect(rows.first[:id]).to include("_type" => "pubid:bipm:meeting", "number" => "14")
      end
    end

    # add_or_update is last-write-wins on a key collision, and crawler.rb hands
    # that collision to the curated static/ doc by indexing it last.
    it "resolves a key collision in favour of the glob given last" do
      in_workdir("data/cctf/meeting/14.yaml" => cctf,
                 "static/cctf/14-curated.yaml" => cctf) do
        described_class.build_index_v2
        expect(index_v2_rows.map { |r| r[:file] }).to eq(["static/cctf/14-curated.yaml"])
        described_class.build_index_v2 globs: ["static/**/*.yaml", "data/**/*.yaml"]
        expect(index_v2_rows.map { |r| r[:file] }).to eq(["data/cctf/meeting/14.yaml"])
      end
    end

    it "rebuilds from scratch rather than merging into a stale index" do
      stale = [{ id: "GONE", file: "data/gone.yaml" }]
      in_workdir("data/cctf/meeting/14.yaml" => cctf,
                 "#{Relaton::Bipm::INDEXFILE}.yaml" => stale) do
        described_class.build_index_v2
        expect(index_v2_rows.map { |r| r[:file] }).to eq(["data/cctf/meeting/14.yaml"])
      end
    end
  end
end
