Gem::Specification.new do |spec|
  spec.name          = "gr_api_manager"
  spec.version       = "0.3.0"
  spec.authors       = ["Razo"]
  spec.email         = ["garabatoangelopolis@gmail.com"]
  spec.summary       = "A minimal Ruby wrapper around Sinatra with auth, file/binary support, rate limiting, and Puma concurrency."
  spec.description   = "Eliminates boilerplate from REST API development. Handles auth, CORS, param validation, type casting, multipart file uploads, raw binary/image/document bodies, Base64, hexadecimal, rate limiting (429), Puma multi-worker concurrency, and dev mode stack traces."
  spec.homepage      = "https://github.com/Gabo-Razo/sinatra-api-manager" 
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sinatra", "~> 3.0"
  spec.add_dependency "dotenv",  "~> 2.8"
  spec.add_dependency "puma",    "~> 5.0"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/README.md"

  spec.post_install_message = "Thanks for installing GR API Manager! Ready to eliminate boilerplate?"
end