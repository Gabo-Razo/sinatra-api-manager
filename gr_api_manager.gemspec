Gem::Specification.new do |spec|
  spec.name          = "gr_api_manager"
  spec.version       = "0.4.0"
  spec.authors       = ["Razo"]
  spec.email         = ["garabatoangelopolis@gmail.com"]
  spec.summary       = "A minimal Ruby wrapper around Sinatra with JWT/Bearer auth, schema validation, route groups, rate limiting, and Puma concurrency."
  spec.description   = "Eliminates boilerplate from REST API development. Handles JWT and Bearer auth, CORS, route groups, declarative schema & type validation, type casting, multipart file uploads, raw binary/image/document bodies, Base64, hexadecimal, sliding-window rate limiting (429), Puma multi-worker concurrency, and dev mode stack traces."
  spec.homepage      = "https://github.com/Gabo-Razo/sinatra-api-manager" 
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "README.md", "README_ES.md"]
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "sinatra", ">= 3.0", "< 5.0"
  spec.add_runtime_dependency "dotenv",  ">= 2.8", "< 4.0"
  spec.add_runtime_dependency "puma",    ">= 5.0", "< 9.0"

  spec.add_development_dependency "rspec",     "~> 3.13"
  spec.add_development_dependency "rack-test", "~> 2.1"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/README.md"

  spec.post_install_message = "Thanks for installing GR API Manager! Ready to eliminate boilerplate?"
end