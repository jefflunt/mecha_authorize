# frozen_string_literal: true

require_relative "lib/mecha_authorize/version"

Gem::Specification.new do |s|
  s.name        = "mecha_authorize"
  s.version     = MechaAuthorize::VERSION
  s.summary     = "Closed-by-default route authorization and auditing for Rails"
  s.description = "MechaAuthorize provides a YAML-driven, closed-by-default route authorization system for Rails applications, complete with static route parity auditing and behavioral persona matrix probing."
  s.authors     = ["Jeff Lunt"]
  s.email       = ["jefflunt@gmail.com"]
  s.homepage    = "https://github.com/jefflunt/mecha_authorize"
  s.license     = "MIT"

  s.required_ruby_version = ">= 3.2.0"

  s.require_paths = ["lib"]
  s.files         = Dir["lib/**/*", "LICENSE", "README.md", "Rakefile"]

  s.add_dependency "activesupport", ">= 7.0"
  s.add_dependency "tiny_color"
end
