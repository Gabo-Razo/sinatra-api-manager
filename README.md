# GR API Manager

[![Gem Version](https://img.shields.io/gem/v/gr_api_manager.svg?logo=rubygems&logoColor=white&color=e9573f)](https://rubygems.org/gems/gr_api_manager)
[![Gem Total Downloads](https://img.shields.io/gem/dt/gr_api_manager.svg?logo=rubygems&logoColor=white&color=00bfa5)](https://rubygems.org/gems/gr_api_manager)
[![Ruby Version](https://img.shields.io/badge/Ruby-%3E%3D%203.0-cc342d.svg?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Sinatra Version](https://img.shields.io/badge/Sinatra-%3E%3D%203.0-008080.svg?logo=sinatra&logoColor=white)](https://sinatrarb.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-007ec6.svg?logo=open-source-initiative&logoColor=white)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-555555.svg?logo=linux&logoColor=white)](https://rubygems.org/gems/gr_api_manager)
[![Tests](https://img.shields.io/badge/Tests-59%2F59%20Passing-4c1.svg?logo=checkmarx&logoColor=white)](spec/)
[![README en Español](https://img.shields.io/badge/README-Espa%C3%B1ol-red.svg?logo=google-translate&logoColor=white)](README_ES.md)

**GR API Manager** is a minimalist, high-performance Ruby wrapper on top of Sinatra and Puma, designed to build production-grade REST APIs with zero boilerplate.

---

## System Requirements

| Dependency / Environment | Required / Supported Version |
|---|---|
| **Ruby** | `>= 3.0` (Tested on 3.0, 3.1, 3.2, 3.3, and 3.4) |
| **Sinatra** | `>= 3.0, < 5.0` |
| **Puma** | `>= 5.0, < 9.0` |
| **Dotenv** | `>= 2.8, < 4.0` |

---

## Key Features

- **Available on RubyGems (`0.4.0`)** - global installation or via Bundler.
- **Modular Route Groups (`api.group`)** - organize large projects into clean, multi-file sub-routers with prefix & option inheritance.
- **Dual Authentication (Static Bearer Token & Native JWT)** - support for pre-shared static tokens and zero-dependency built-in HMAC-SHA256 JWT engine.
- **Declarative Schema & Type Validation** - validate complex request contracts with `:email`, `:url`, `:boolean`, `:file`, classes (`Integer`, `Float`, `String`, `Array`, `Hash`), enum lists, regular expressions, or custom procs.
- **Sliding-Window Rate Limiting (429)** - sliding-window rate limiter with automatic client IP detection behind Cloudflare (`CF-Connecting-IP`), Nginx (`X-Real-IP`), or Reverse Proxies (`X-Forwarded-For`), supporting in-memory or pluggable stores (Redis).
- **Smart Parameter Casting** - automatic type casting for query and URL parameters (`"100"` -> `100`, `"-42"` -> `-42`, `"true"` -> `true`, `"19.99"` -> `19.99`).
- **Unified File & Binary Handling (`FilePayload`)** - transparent handling for multipart uploads, raw binary streams, Base64/Hex encoding, file serving/downloads, and disk storage with directory auto-creation.
- **Puma Concurrency** - configurable multi-process workers and thread pools.
- **Developer Mode (`dev_mode`)** - structured JSON error responses with full stack traces for painless debugging.

---

## Installation

Add the gem to your `Gemfile`:
```ruby
gem 'gr_api_manager', '~> 0.4.0'
```

And run:
```bash
bundle install
```

Or install directly:
```bash
gem install gr_api_manager
```

---

## Table of Contents

1. [Quickstart](#quickstart)
2. [Authentication: Static Bearer Token & Native JWT](#authentication-static-bearer-token--native-jwt)
3. [Multi-File Modular Architecture (Importing & Grouping)](#multi-file-modular-architecture)
4. [Full REST CRUD with HTTP Verbs](#full-rest-crud-with-http-verbs)
5. [Declarative Schema & Type Validation](#declarative-schema--type-validation)
6. [Comprehensive File, Binary & Image Handling](#comprehensive-file-binary--image-handling)
7. [Serving & Downloading Files to Clients](#serving--downloading-files-to-clients)
8. [Rate Limiting & Real IP Detection (Cloudflare/Nginx)](#rate-limiting--real-ip-detection)
9. [Smart Parameter Casting](#smart-parameter-casting)
10. [Responses, HTTP Status Codes & Dev Mode](#responses-http-status-codes--dev-mode)
11. [Concurrency & Production Deployment (Puma & Docker)](#concurrency--production-deployment)

---

## Quickstart

Create an `app.rb` file:

```ruby
require 'gr_api_manager'

# Initialize the server with static token and JWT key
api = GRApiManager::Server.new(
  port: 4000,
  bearer_token: "my_static_secret_token",
  jwt_secret: "my_jwt_signing_secret"
)

# Public endpoint (no auth required)
api.get('/health', auth: false) do
  { status: 'online', timestamp: Time.now.to_i }
end

# Protected endpoint with static token (default: auth = true)
api.get('/protected-data') do
  { message: "Access granted with Bearer Token", data: [10, 20, 30] }
end

# Start the server
api.run!
```

Run your API:
```bash
ruby app.rb
```

---

## Authentication: Static Bearer Token & Native JWT

`gr_api_manager` supports two complementary authentication schemes:

### 1. Static Bearer Token

Ideal for internal services, webhooks, microservices, or backend automation using a pre-shared static key.

#### Configuration in `app.rb`:
```ruby
api = GRApiManager::Server.new(
  bearer_token: "my_secret_company_token_2026"
)

# Public route
api.get('/public', auth: false) do
  { status: "open access" }
end

# Protected routes (default auth: true)
api.get('/admin/config') do
  { database: "connected", environment: "production" }
end

api.post('/admin/restart', requires: [:reason]) do |params|
  { action: "restarting", reason: params[:reason] }
end
```

#### Consuming via cURL:

**Valid request (200 OK):**
```bash
curl -H "Authorization: Bearer my_secret_company_token_2026" http://localhost:4000/admin/config
# => {"database":"connected","environment":"production"}
```

**Missing Authorization header (401 Unauthorized):**
```bash
curl http://localhost:4000/admin/config
# => 401 {"error":"Token required. Format: 'Bearer <token>'"}
```

**Invalid token (403 Forbidden):**
```bash
curl -H "Authorization: Bearer wrong_token" http://localhost:4000/admin/config
# => 403 {"error":"Invalid token"}
```

---

### 2. Native JWT Authentication (HS256)

Ideal for end-user facing APIs issuing dynamic tokens with expiration and claims.

#### Complete Workflow:
```ruby
api = GRApiManager::Server.new(
  jwt_secret: "my_super_secret_jwt_key"
)

# 1. Login: issue and return token
api.post('/auth/login', auth: false, requires: { email: :email, password: String }) do |params|
  if params[:email] == "admin@company.com" && params[:password] == "pass123"
    token = api.jwt_encode(
      { user_id: 42, email: params[:email], role: "admin" },
      exp: Time.now.to_i + 3600 # 1-hour expiration
    )
    { token: token, token_type: "Bearer", expires_in: 3600 }
  else
    status 401
    { error: "Invalid credentials" }
  end
end

# 2. JWT-protected route: automatically injects params[:current_user]
api.get('/profile', auth: :jwt) do |params|
  user = params[:current_user]
  {
    message: "Valid JWT token",
    user_id: user[:user_id],
    email: user[:email],
    role: user[:role]
  }
end
```

---

## Multi-File Modular Architecture

Divide your API into dedicated, clean route modules within a `routes/` directory:

```text
my_api_project/
├── app.rb                   # Main entrypoint and configuration
├── .env                     # Environment variables
├── Gemfile
└── routes/
    ├── auth_routes.rb       # Login & registration
    ├── admin_routes.rb      # Admin dashboard
    ├── payments_routes.rb   # Checkout & billing
    └── files_routes.rb      # File uploads & storage
```

### Module 1: `routes/auth_routes.rb`
```ruby
module AuthRoutes
  def self.setup(router, api_server)
    router.post('/login', auth: false, requires: { email: :email, password: String }) do |params|
      if params[:email] == "admin@company.com" && params[:password] == "secret"
        token = api_server.jwt_encode({ user_id: 1, email: params[:email], role: "admin" })
        { token: token }
      else
        status 401
        { error: "Invalid credentials" }
      end
    end
  end
end
```

### Module 2: `routes/admin_routes.rb`
```ruby
module AdminRoutes
  def self.setup(router)
    router.get('/metrics') do |params|
      { cpu: "12%", memory: "380MB", user: params[:current_user][:email] }
    end

    router.delete('/users/:id') do |params|
      { message: "User #{params[:id]} deleted" }
    end
  end
end
```

### Module 3: `routes/files_routes.rb`
```ruby
module FilesRoutes
  def self.setup(router)
    router.post('/upload', requires: [:title]) do |params|
      file = params[:_files][:document]
      path = file.save_to("./storage/#{params[:title]}#{file.extension}")
      { status: "saved", path: path, size: file.size }
    end
  end
end
```

### Main Application File: `app.rb`
```ruby
require 'gr_api_manager'

# Require modular route files
require_relative 'routes/auth_routes'
require_relative 'routes/admin_routes'
require_relative 'routes/files_routes'

api = GRApiManager::Server.new(
  port: 4000,
  jwt_secret: ENV['JWT_SECRET'] || "default_jwt_secret",
  bearer_token: ENV['API_TOKEN'] || "global_static_token"
)

# Root route
api.get('/', auth: false) { { service: "Core API v1.0" } }

# Mount route groups
api.group('/auth') { |g| AuthRoutes.setup(g, api) }
api.group('/admin', auth: :jwt) { |g| AdminRoutes.setup(g) }
api.group('/files', auth: true) { |g| FilesRoutes.setup(g) }

api.run!(workers: 2, threads: '2:8')
```

---

## Full REST CRUD with HTTP Verbs

Example managing a `/products` resource:

```ruby
api = GRApiManager::Server.new(prefix: '/api/v1')

# 1. LIST (GET) - with auto-cast query parameters
api.get('/products', auth: false) do |params|
  page   = params[:page] || 1        # Integer
  limit  = params[:limit] || 10      # Integer
  active = params[:active] != false  # Boolean
  
  {
    page: page,
    limit: limit,
    items: [
      { id: 1, name: "Mechanical Keyboard", price: 89.99, active: true },
      { id: 2, name: "4K Monitor", price: 299.99, active: true }
    ]
  }
end

# 2. GET BY ID (GET)
api.get('/products/:id', auth: false) do |params|
  id = params[:id] # Auto Integer
  { id: id, name: "Product #{id}", price: 49.99 }
end

# 3. CREATE (POST) - with strong type validation
api.post('/products', requires: { name: String, price: Float, category: ['tech', 'office'] }) do |params|
  status 201
  {
    message: "Product created",
    product: { id: rand(100..999), name: params[:name], price: params[:price] }
  }
end

# 4. FULL UPDATE (PUT)
api.put('/products/:id', requires: { name: String, price: Float }) do |params|
  {
    message: "Product #{params[:id]} completely updated",
    data: params
  }
end

# 5. PARTIAL UPDATE (PATCH)
api.patch('/products/:id') do |params|
  {
    message: "Updated fields for product #{params[:id]}",
    changes: params.except(:id)
  }
end

# 6. DELETE (DELETE)
api.delete('/products/:id') do |params|
  { message: "Product #{params[:id]} deleted successfully" }
end
```

---

## Declarative Schema & Type Validation

The `requires:` option validates data types, string formats, uploaded files, and custom logic:

```ruby
api.post '/catalog', requires: {
  sku:         /^[A-Z]{3}-\d{4}$/,           # Regexp: e.g. "PRO-1234"
  title:       String,                       # Non-empty string
  price:       Float,                        # Float number
  stock:       Integer,                      # Integer
  active:      :boolean,                     # true or false
  category:    ['electronics', 'home'],      # Enum / List of allowed values
  photo:       :file,                        # Uploaded FilePayload
  website:     :url,                         # Valid URL (http/https)
  contact:     :email,                       # Valid email address
  discount:    ->(v) { v.to_f.between?(0, 100) } # Custom Lambda validation
} do |params|
  status 201
  { status: "ok", item: params[:title] }
end
```

### Supported Validation Rules:

| Rule | Expected Format / Type | Valid Example |
|---|---|---|
| `:email` | Standard email format | `"contact@domain.com"` |
| `:url` | URL with `http://` or `https://` | `"https://api.domain.com"` |
| `:boolean` | Native boolean (`true` or `false`) | `true`, `false` |
| `:file` | Instance of `GRApiManager::FilePayload` | Multipart file upload |
| `Integer` | Integer number | `42`, `100`, `-10` |
| `Float` | Floating point number | `19.99`, `0.5`, `-3.14` |
| `Numeric` | Any numeric value (`Integer` or `Float`) | `10`, `3.14` |
| `String` | Non-empty string | `"Sample Text"` |
| `Array` | Array of elements | `[1, 2, 3]` |
| `Hash` | JSON Object or Hash | `{ key: "value" }` |
| `['a', 'b']` | Exact inclusion in list (Enum) | `'electronics'` |
| `/^regex$/` | Regular expression match | `"ABC-1234"` |
| `->(val) { ... }` | Custom Lambda/Proc (must return `true`) | `->(n) { n.to_i > 0 }` |

---

## Comprehensive File, Binary & Image Handling

`gr_api_manager` detects incoming `Content-Type` headers and provides uniform file handling via `FilePayload`:

### 1. Multipart Form Upload (`multipart/form-data`)
```ruby
api.post('/profile/avatar', requires: [:user_id]) do |params|
  avatar = params[:_files][:avatar] # FilePayload instance

  # Save to disk (creates directories automatically if missing)
  saved_path = avatar.save_to("./storage/avatars/user_#{params[:user_id]}#{avatar.extension}")

  {
    message: "Avatar saved",
    filename: avatar.filename,
    size: avatar.size,
    extension: avatar.extension,
    saved_path: saved_path
  }
end
```

#### cURL multipart:
```bash
curl -X POST http://localhost:4000/profile/avatar \
  -H "Authorization: Bearer my_token" \
  -F "user_id=10" \
  -F "avatar=@/path/to/my_photo.jpg"
```

---

### 2. Raw Binary Upload (Image / PDF / Octet-Stream)

Direct raw byte streaming in request body (no multipart form):

```ruby
api.post('/documents/raw') do |params|
  file = params[:_raw_binary] # FilePayload instance

  file.save_to("./storage/docs/#{file.filename}")
  
  {
    format: "raw binary",
    detected_filename: file.filename,
    size_bytes: file.size,
    mime_type: file.content_type,
    initial_hex: file.to_hex[0..30]
  }
end
```

#### cURL raw binary:
```bash
curl -X POST http://localhost:4000/documents/raw \
  -H "Authorization: Bearer my_token" \
  -H "Content-Type: application/pdf" \
  -H "Content-Disposition: attachment; filename=\"contract.pdf\"" \
  --data-binary @contract.pdf
```

---

### 3. Base64 and Hexadecimal Conversion
```ruby
api.post('/files/convert') do |params|
  file = params[:_files][:file]

  {
    base64: file.to_base64, # Clean Base64 string without newlines
    hexadecimal: file.to_hex, # Lowercase hex string
    total_bytes: file.size
  }
end
```

---

### 4. Plain Text Upload (`text/plain`)
```ruby
api.post('/logs/text') do |params|
  raw_text = params[:_raw_text] # UTF-8 String
  { lines: raw_text.lines.count, characters: raw_text.length }
end
```

---

## Serving & Downloading Files to Clients

When a route block returns a `String`, `gr_api_manager` serves it **directly as raw data**, allowing seamless downloads of images, PDFs, or binary streams:

```ruby
api.get('/downloads/photo/:id', auth: false) do |params|
  photo_path = "./storage/avatars/user_#{params[:id]}.jpg"
  
  unless File.exist?(photo_path)
    status 404
    next { error: "Photo not found" }
  end

  # Configure response headers
  content_type 'image/jpeg'
  headers 'Content-Disposition' => "inline; filename=\"photo_#{params[:id]}.jpg\""
  
  # Return binary bytes directly
  File.binread(photo_path)
end
```

---

## Rate Limiting & Real IP Detection

Protect your API with thread-safe sliding-window rate limiting per client IP:

```ruby
api = GRApiManager::Server.new(
  rate_limit:          60,   # Max 60 requests
  rate_limit_window:   60,   # per 60-second window
  trust_proxy_headers: true  # Reads CF-Connecting-IP, X-Real-IP, X-Forwarded-For
)
```

Standard HTTP response headers:
* `X-RateLimit-Limit`: Maximum allowed requests (`60`).
* `X-RateLimit-Remaining`: Remaining requests in current window.
* `X-RateLimit-Reset`: Unix timestamp when quota resets.
* `Retry-After`: Seconds to wait if rate-limited (`429 Too Many Requests`).

---

## Smart Parameter Casting

URL and Query String parameters are automatically converted to native Ruby types before entering your route block:

```ruby
api.get('/analytics') do |params|
  # Request: /analytics?id=123&active=true&discount=15.5&balance=-500&category=tech
  
  params[:id]        # => 123 (Integer)
  params[:active]    # => true (TrueClass)
  params[:discount] # => 15.5 (Float)
  params[:balance]   # => -500 (Integer)
  params[:category]  # => "tech" (String)
  
  { status: "ok" }
end
```

---

## Responses, HTTP Status Codes & Dev Mode

### Custom status codes:
```ruby
api.post('/resources') do
  status 201 # Created
  { message: "Resource created" }
end
```

### Developer Mode (`dev_mode: true`):
Enable `dev_mode: true` to receive structured JSON error payloads with full stack traces during development:

```ruby
api = GRApiManager::Server.new(dev_mode: true)
```

Error response on 500:
```json
{
  "error": "Internal Server Error",
  "details": "undefined local variable or method 'missing_var'",
  "class": "NameError",
  "backtrace": [
    "/app/routes/users.rb:14:in `block in setup'",
    "/lib/gr_api_manager.rb:482:in `instance_exec'"
  ]
}
```

---

## Concurrency & Production Deployment

### Running with Puma in Production:
```ruby
# Start with 4 worker processes and 4:16 threads per worker
api.run!(workers: 4, threads: '4:16')
```

### Production `Dockerfile`:
```dockerfile
FROM ruby:3.3-slim

WORKDIR /app
COPY Gemfile* ./
RUN bundle install --without development test

COPY . .

EXPOSE 4000
CMD ["ruby", "app.rb"]
```

---

## Automated Testing

Full test suite with **RSpec** and **Rack::Test**:

```bash
rspec
# => 59 examples, 0 failures
```

---

## License

This project is licensed under the [MIT](LICENSE) License. Created by **Gabo Razo**.
