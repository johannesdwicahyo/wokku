Gem::Specification.new do |spec|
  spec.name          = "wokku-cli"
  spec.version       = "0.1.0"
  spec.authors       = [ "Johannes Dwicahyo" ]
  spec.summary       = "CLI for Wokku - Heroku-like PaaS on Dokku"
  spec.homepage      = "https://wokku.dev"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.files         = Dir["lib/**/*", "exe/*"]
  spec.bindir        = "exe"
  spec.executables   = [ "wokku" ]
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "pastel", "~> 0.8"
end
