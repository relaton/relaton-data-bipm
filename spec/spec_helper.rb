# frozen_string_literal: true

require "fileutils"
require "yaml"
require "tmpdir"

require_relative "../index_builder"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  # `Relaton::Index::Pool#type` reuses a pooled index whenever the requested
  # url/file match, and `Relaton::Index::Type` keeps the parsed rows in memory.
  # Both index-v2 builders ask for the same `index-v2.yaml`, so without this an
  # example would inherit the rows another example built in a since-deleted
  # temporary working directory.
  config.before { Relaton::Index.close :bipm }
end

# Run a block inside a throwaway working directory seeded with the given
# doc fixtures (relative path => YAML hash), so the CWD-relative index globs
# and `index-*.yaml` writes never touch the repo.
def in_workdir(docs)
  Dir.mktmpdir do |dir|
    docs.each do |rel, content|
      path = File.join(dir, rel)
      FileUtils.mkdir_p File.dirname(path)
      File.write path, content.to_yaml
    end
    Dir.chdir(dir) { yield dir }
  end
end
