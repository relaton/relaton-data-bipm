# frozen_string_literal: true
source 'https://rubygems.org'

# Pin to `main` explicitly: it is relaton's default branch, but an unpinned
# `github:` freezes whatever branch was current into Gemfile.lock, and relaton's
# remote churns many transient feature branches. Pinning `main` keeps any
# regenerated lock on a permanent ref so `bundle update` can't fail fetching a
# deleted feature branch (e.g. the merged-and-deleted `upd-lutaml-model-to-0.8.0`).
gem 'relaton', github: 'relaton/relaton', branch: 'main'
# Temporary: pin pubid to metanorma/pubid `main` for the `Pubid::Bipm` flavor.
# The published pubid gem (2.0.0.pre.alpha.8) predates that flavor, and a git
# gem's gemspec (relaton's) can't carry a git source, so bundler would otherwise
# resolve the stale published pubid and the crawl dies with
# `uninitialized constant Pubid::Bipm`, never writing index-v2. Remove once
# pubid publishes a release carrying the Bipm flavor.
gem 'pubid', github: 'metanorma/pubid', branch: 'main'

group :test do
  gem 'rspec', '~> 3.13'
end
