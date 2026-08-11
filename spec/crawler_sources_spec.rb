# frozen_string_literal: true

require "spec_helper"

# Guards the crawler's source-repo clone step.
#
# `crawler.rb` reads three sibling checkouts it clones itself
# (`bipm-data-outcomes`, `bipm-si-brochure`, `rawdata-bipm-metrologia`). All
# three are in `.gitignore` and are usually already present in a development
# checkout, which makes commenting the clones out a convenient — and easily
# committed — local shortcut. That is exactly what shipped in 26822298ff, and
# CI died 41s in with
# `No such file or directory - bipm-si-brochure/metanorma.yml`.
#
# `crawler.rb` is a top-level script that clones and network-fetches on load, so
# it cannot be required here; these assertions read it as source text instead.
RSpec.describe "crawler.rb source repositories" do
  SOURCE_REPOS = %w[bipm-data-outcomes bipm-si-brochure rawdata-bipm-metrologia].freeze

  crawler_path = File.expand_path("../crawler.rb", __dir__)
  source = File.read(crawler_path)

  # Lines that actually execute — commented-out code is not a clone.
  let(:active_lines) { source.lines.reject { |l| l.strip.start_with?("#") } }

  # Every executable `fast_fail_system` clone, as
  # [dir it clones into, surrounding source window]. The window spans the
  # neighbouring lines so a guard/label written either inline or as an enclosing
  # `unless` block counts the same.
  let(:clone_statements) do
    lines = source.lines
    lines.each_with_index.filter_map do |line, i|
      next if line.strip.start_with?("#")

      command = line[/fast_fail_system\(\s*(['"])(.*?)\1/, 2]
      next unless command&.include?("git clone")

      [command.split.last, lines[[i - 3, 0].max..(i + 3)].join]
    end
  end

  let(:cloned_dirs) { clone_statements.map(&:first) }

  # Directories `crawler.rb` consumes afterwards, via `chdir:` build steps and
  # `DataFetcher.fetch`. Derived from the source so a newly added source that
  # nobody clones fails this spec too.
  let(:consumed_dirs) do
    active_lines.filter_map do |line|
      path = line[/chdir:\s*(['"])(.*?)\1/, 2] ||
             line[/DataFetcher\.fetch\(?\s*(['"])(.*?)\1/, 2]
      path&.split("/")&.first
    end.uniq
  end

  it "clones the three known source repositories" do
    expect(cloned_dirs).to contain_exactly(*SOURCE_REPOS)
  end

  it "clones every source directory it later builds in or fetches from" do
    # Pinned exactly, so rewording a `chdir:`/`fetch` call out of the patterns
    # above erodes coverage loudly instead of silently.
    expect(consumed_dirs).to contain_exactly(*SOURCE_REPOS)
    expect(consumed_dirs - cloned_dirs).to be_empty
  end

  it "leaves no clone call commented out" do
    # Matches disabled *code*, not prose — a comment that merely mentions
    # `git clone` (this file's own explanatory header does) is fine.
    commented = source.lines.grep(/^\s*#\s*fast_fail_system.*git clone/)
    expect(commented).to be_empty
  end

  it "skips a clone whose checkout is already present, so reruns work" do
    # A bare `git clone` into an existing directory exits 128 and fast-fails the
    # whole crawl, which is what makes disabling the clones tempting locally.
    # Each clone must therefore be guarded by an existence check on its own dir.
    clone_statements.each do |dir, window|
      expect(window).to match(/unless\s+Dir\.exist\?\(\s*(['"])#{Regexp.escape(dir)}\1\s*\)/),
                        "clone of `#{dir}` is not guarded by `unless Dir.exist?('#{dir}')`"
    end
  end

  it "keeps the credentialed clone out of fast_fail_system's error output" do
    # `fast_fail_system` echoes the failing command; the metrologia URL embeds
    # RELATON_CI_PAT, so that call must pass a redacted `label:` instead.
    _dir, window = clone_statements.find { |dir, _| dir == "rawdata-bipm-metrologia" }
    expect(window).to include("relaton_ci_pat")
    label = window[/label:\s*(['"])(.*?)\1/, 2]
    expect(label).to be_a(String), "credentialed clone passes no `label:` to fast_fail_system"
    expect(label).not_to include("relaton_ci_pat")
  end

  it "clones the repository holding the metanorma.yml it rewrites" do
    yml_path = source[/yml_path\s*=\s*(['"])(.*?)\1/, 2]
    expect(yml_path).to eq("bipm-si-brochure/metanorma.yml")
    expect(cloned_dirs).to include(yml_path.split("/").first)
  end
end
