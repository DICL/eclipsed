# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'eclipsed/version'

Gem::Specification.new do |spec|
  spec.name          = "eclipsed"
  spec.version       = Eclipsed::VERSION
  spec.authors       = ["Vicente Adolfo Bolea Sanchez"]
  spec.email         = ["vicente.bolea@gmail.com"]

  if spec.respond_to?(:metadata)
    #spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com' to prevent pushes to rubygems.org, or delete to allow pushes to any server."
  end

  spec.summary       = %q{EclipseDFS governor}
  spec.description   = %q{Controls EclipseDFS.}
  spec.homepage      = "http://dicl.unist.ac.kr"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.8"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency "awesome_print"
  spec.add_runtime_dependency "table_print"
  spec.add_runtime_dependency "pry"
  spec.required_ruby_version = '>= 2.0'
end
