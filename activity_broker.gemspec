# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'activity_broker/version'

Gem::Specification.new do |spec|
  spec.name          = "activity_broker"
  spec.version       = ActivityBroker::VERSION
  spec.authors       = ["Oliver Martell"]
  spec.email         = ["oliver.martell@gmail.com"]
  spec.summary       = %q{Twitter like notifications, TCP Sockets, Event loops and more}
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
