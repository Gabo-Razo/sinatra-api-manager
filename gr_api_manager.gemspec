Gem::Specification.new do |spec|
  spec.name          = "gr_api_manager"
  spec.version       = "0.1.0"
  spec.authors       = ["Razo"]
  spec.email         = ["garabatoangelopolis@gmail.com"]
  spec.summary       = "A minimal, opinionated Ruby wrapper around Sinatra."
  spec.description   = "Eliminates boilerplate from REST API development. Handles Auth, CORS, parameter validation, and type casting."
  spec.homepage      = "https://github.com/Gabo-Razo/sinatra-api-manager" 
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sinatra", "~> 3.0"
  spec.add_dependency "dotenv", "~> 2.8"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/README.md"

  spec.post_install_message = "Thanks for installing GR API Manager! Ready to eliminate boilerplate?"
end