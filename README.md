# GR API Manager

[![Gem Version](https://badge.fury.io/rb/gr-api-manager.svg)](https://rubygems.org/gems/gr-api-manager)
[![README en Español](https://img.shields.io/badge/README-Español-blue)](README_ES.md)

A minimal Ruby wrapper around Sinatra that eliminates boilerplate from REST API development. Auth, parameter validation, type casting, CORS, error handling, **file uploads, raw binaries, images, Base64 and hexadecimal** — all at the framework level. You write only the business logic.

---

## Features

- Available on **RubyGems** — install globally, use anywhere.
- Route-level Bearer Token auth (on/off per endpoint).
- Declarative required parameter validation → automatic `400 Bad Request`.
- Smart type casting: `"10"` → `Integer`, `"true"` → `TrueClass`, `"9.5"` → `Float`.
- Global JSON error responses for `404`, `500`, and `413`.
- Broad CORS and preflight `OPTIONS` out of the box.
- API versioning via configurable route prefix (`/api/v1`, `/geo/v2`, etc.).
- **Full binary & file support** — multipart, raw binary, Base64, hex, `text/plain`.
- Configurable body size limit with `mb` / `gb` helpers.
- **Dev mode** — full stack traces on `500` for easier debugging.

---

## Installation

```ruby
gem 'gr-api-manager'   # Gemfile
```

```bash
bundle install
# or: gem install gr-api-manager
```

---

## Quick Start — name it anything you want

The `Server` object is just a Ruby object. Call it `api`, `app`, `pais_api`, `backend`, `mi_servicio` — whatever fits your project. There is no magic name.

```ruby
require 'gr_api_manager'

# Any name works
api      = GRApiManager::Server.new(port: 4567, bearer_token: "secret")
pais_api = GRApiManager::Server.new(prefix: "/geo/v1")
reports  = GRApiManager::Server.new(port: 5000, max_body_size: GRApiManager.gb(1))

api.get('/health', auth: false) { { status: 'ok' } }
api.run!
```

---

## Configuration

```ruby
GRApiManager::Server.new(
  port:            4567,
  bearer_token:    "secret",
  permitted_hosts: ["example.com"],   # empty = allow all
  prefix:          "/api/v1",
  max_body_size:   GRApiManager.mb(50),  # default 50 MB
  dev_mode:        false                 # default false
)
```

### Size helpers

Express limits cleanly without doing manual math:

```ruby
GRApiManager.mb(50)    # 50 megabytes
GRApiManager.mb(200)   # 200 megabytes — for large file uploads
GRApiManager.gb(1)     # 1 gigabyte   — for heavy reports or video

# Examples
video_api  = GRApiManager::Server.new(max_body_size: GRApiManager.gb(2))
json_api   = GRApiManager::Server.new(max_body_size: GRApiManager.mb(1))
report_api = GRApiManager::Server.new(max_body_size: GRApiManager.mb(500))
```

### `.env` file (recommended for production)

```env
PORT=4567
API_TOKEN=your_secret_token
```

```ruby
api = GRApiManager::Server.new   # picks up PORT and API_TOKEN automatically
```

Explicit arguments always override `.env`. Add `.env` to `.gitignore`.

---

## HTTP Verbs — what each one does

| Method | Purpose | Typical use |
|---|---|---|
| `GET` | **Read** — fetch data, no side effects | List, search, get by ID |
| `POST` | **Create** — add a new resource | Create user, upload file |
| `PUT` | **Full replace** — replace an existing resource entirely | Update full user profile |
| `PATCH` | **Partial update** — modify specific fields only | Change only an email |
| `DELETE` | **Remove** — delete a resource | Delete user, remove file |

```ruby
api.get('/users')         { ... }   # list
api.get('/users/:id')     { ... }   # read one
api.post('/users')        { ... }   # create
api.put('/users/:id')     { ... }   # full replace
api.patch('/users/:id')   { ... }   # partial update
api.delete('/users/:id')  { ... }   # delete
```

---

## Defining Routes

```ruby
api.post('/path', auth: true, requires: [:name, :email]) do |params|
  # params — merged hash: URL segments + query string (type-cast) + parsed body
  { result: "ok" }
end
```

| Option | Type | Default | Description |
|---|---|---|---|
| `auth` | Boolean | `true` | Require Bearer Token |
| `requires` | Array | `[]` | Required parameter keys |

---

## Success Responses

Return any Hash or Array — the framework serializes to JSON automatically.

```ruby
# Simple hash
api.get('/ping', auth: false) { { pong: true } }

# Set a status code
api.post('/users', requires: [:name]) do |params|
  status 201
  { message: "Created", user: { name: params[:name] } }
end

# Short-circuit with next
api.get('/users/:id') do |params|
  if params[:id] == 0
    status 404
    next { error: "Not found" }
  end
  { id: params[:id], name: "Alice" }
end
```

> Returning a `String` sends it **as-is** (no JSON wrapping) — useful for binary file responses.

---

## Authentication

```ruby
api.get('/health', auth: false) { { status: 'online' } }  # public

api.get('/data') do |params|    # protected (default)
  { secret: "data" }
end
```

```bash
curl -H "Authorization: Bearer your_token" http://localhost:4567/api/v1/data
```

```json
// 401 — missing header
{ "error": "Token required. Format: 'Bearer <token>'" }

// 403 — wrong token
{ "error": "Invalid token" }
```

---

## Parameter Validation

```ruby
api.post('/users', requires: [:name, :email, :role]) do |params|
  status 201
  { message: "User created", user: params }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: application/json" \
  -d '{"name":"Gabo"}'

# => 400 { "error": "Missing required parameters", "required": ["email", "role"] }
```

---

## Smart Type Casting

Query string values are cast to native Ruby types before reaching your block:

| String | Ruby type | Value |
|---|---|---|
| `"42"` | Integer | `42` |
| `"3.14"` | Float | `3.14` |
| `"true"` | TrueClass | `true` |
| `"false"` | FalseClass | `false` |

```bash
curl "http://localhost:4567/api/v1/products?page=2&active=true&price=9.99"
# params => { page: 2, active: true, price: 9.99 }
```

---

## File & Binary Body Handling

The framework auto-detects `Content-Type` and parses accordingly. **No extra setup needed.**

### Supported body formats

| Content-Type | What you get in `params` |
|---|---|
| `application/json` | Regular symbolized hash |
| `multipart/form-data` | Text fields + `:_files` → `{ field: FilePayload }` |
| `image/*`, `video/*`, `audio/*` | `:_raw_binary` → `FilePayload` |
| `application/pdf`, `application/msword`, `application/vnd.*` | `:_raw_binary` → `FilePayload` |
| `application/octet-stream` | `:_raw_binary` → `FilePayload` |
| `text/plain` | `:_raw_text` → `String` |

### `FilePayload` API

| Method | Returns | Description |
|---|---|---|
| `#read` | `String` (binary) | Raw bytes |
| `#to_base64` | `String` | Base64-encoded (no newlines) |
| `#to_hex` | `String` | Lowercase hexadecimal string |
| `#save_to(path)` | `String` | Save to disk, returns path |
| `#filename` | `String` | Original filename |
| `#content_type` | `String` | MIME type |
| `#size` | `Integer` | Size in bytes |
| `#extension` | `String` | Extension (`.jpg`, `.pdf`, etc.) |
| `#to_h` | `Hash` | JSON-safe summary |

### Multipart image upload

```ruby
api.post('/upload/avatar', auth: true) do |params|
  file = params[:_files][:avatar]
  halt 400, { error: 'Field "avatar" required' }.to_json unless file
  halt 400, { error: "Invalid type" }.to_json unless %w[.jpg .png .webp].include?(file.extension)

  file.save_to("/uploads/#{file.filename}")
  status 201
  { message: "Uploaded", file: file.to_h }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/upload/avatar \
  -H "Authorization: Bearer secret" \
  -F "avatar=@photo.jpg"
```

### Multiple files in one request

```ruby
api.post('/documents', auth: true) do |params|
  files = params[:_files] || {}
  halt 400, { error: 'No files received' }.to_json if files.empty?

  saved = files.map { |_, f| f.save_to("/uploads/#{f.filename}"); f.to_h }
  status 201
  { uploaded: saved }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/documents \
  -H "Authorization: Bearer secret" \
  -F "doc=@report.pdf" -F "thumbnail=@thumb.png"
```

### Raw binary body (image, PDF, Word, etc.)

```ruby
api.post('/files/raw', auth: true) do |params|
  file = params[:_raw_binary]
  halt 400, { error: 'Binary body required' }.to_json unless file

  path = file.save_to("/uploads/#{file.filename}")
  { saved_to: path, magic_bytes: file.to_hex[0, 8], size: file.size }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/files/raw \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: image/png" --data-binary @photo.png

curl -X POST http://localhost:4567/api/v1/files/raw \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: application/pdf" --data-binary @doc.pdf
```

### Base64 inside JSON

```ruby
require 'base64'

api.post('/files/base64', auth: true, requires: [:data, :filename]) do |params|
  raw  = Base64.strict_decode64(params[:data])
  File.open("/uploads/#{params[:filename]}", 'wb') { |f| f.write(raw) }
  { message: "Saved", bytes: raw.bytesize }
end
```

```bash
BASE64=$(base64 -w0 photo.jpg)
curl -X POST http://localhost:4567/api/v1/files/base64 \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: application/json" \
  -d "{\"filename\":\"photo.jpg\",\"data\":\"$BASE64\"}"
```

### Hexadecimal

```ruby
api.post('/files/tohex', auth: true) do |params|
  file = params[:_raw_binary]
  halt 400, { error: 'Binary body required' }.to_json unless file
  # to_hex converts any binary to a lowercase hex string
  { hex: file.to_hex, bytes: file.size }
end
```

### Plain text body

```ruby
api.post('/notes', auth: true) do |params|
  text = params[:_raw_text]
  halt 400, { error: 'Empty body' }.to_json if text.nil? || text.strip.empty?
  { received: text, words: text.split.size }
end
```

### Serving a file as binary response

```ruby
api.get('/files/:name', auth: true) do |params|
  path = "/uploads/#{File.basename(params[:name].to_s)}"
  halt 404, { error: "Not found" }.to_json unless File.exist?(path)

  content_type 'application/octet-stream'
  response.headers['Content-Disposition'] = "attachment; filename=\"#{File.basename(path)}\""
  File.binread(path)   # String → sent as-is, no JSON wrapping
end
```

### Body size limit

```json
// When exceeded → 413
{ "error": "Payload too large", "max_bytes": 52428800 }
```

```ruby
GRApiManager::Server.new(max_body_size: GRApiManager.mb(200))  # 200 MB
GRApiManager::Server.new(max_body_size: GRApiManager.gb(2))    # 2 GB
GRApiManager::Server.new(max_body_size: GRApiManager.mb(1))    # 1 MB
```

---

## Dev Mode

Enable during development for full stack traces on `500` errors:

```ruby
api = GRApiManager::Server.new(
  bearer_token: "secret",
  dev_mode: true   # ⚠️ Disable in production
)
```

**Production (dev_mode: false):**
```json
{ "error": "Internal Server Error", "details": "undefined method 'foo' for nil" }
```

**Development (dev_mode: true):**
```json
{
  "error": "Internal Server Error",
  "details": "undefined method 'foo' for nil",
  "class": "NoMethodError",
  "backtrace": ["app.rb:42:in 'block in register_route'", "..."]
}
```

---

## Error Handling

```json
// 404
{ "error": "Endpoint not found", "path": "/api/v1/missing" }

// 500
{ "error": "Internal Server Error", "details": "..." }

// 413
{ "error": "Payload too large", "max_bytes": 52428800 }
```

---

## Request Logging

```text
[14:32:01] GET  /api/v1/health - 200
[14:32:05] POST /api/v1/users - 400
[14:32:10] POST /api/v1/upload/avatar - 201
```

Green for 2xx, red for everything else.

---

## Running the Server

```text
=============================================
  GR API MANAGER STARTED
  Port      : 4567
  Auth      : Enabled
  Prefix    : /api/v1
  Max Body  : 50.0 MB
  Dev Mode  : Off
=============================================
```

---

## Complete Example — Country API

This shows how the framework handles a real-world CRUD API with file uploads. Note that the server is named `pais_api` — **you can name it anything**.

```ruby
require 'gr_api_manager'
require 'fileutils'

FileUtils.mkdir_p('/uploads/flags')

pais_api = GRApiManager::Server.new(
  port:          4567,
  bearer_token:  "geo_secret_2024",
  prefix:        "/geo/v1",
  max_body_size: GRApiManager.mb(5),
  dev_mode:      true
)

COUNTRIES = [
  { id: 1, name: "Mexico",    capital: "Mexico City",  pop: 128_000_000, continent: "North America" },
  { id: 2, name: "Argentina", capital: "Buenos Aires", pop: 45_000_000,  continent: "South America" },
  { id: 3, name: "Spain",     capital: "Madrid",       pop: 47_000_000,  continent: "Europe" }
]

# GET — list all (public)
pais_api.get('/countries', auth: false) do
  { total: COUNTRIES.size, countries: COUNTRIES }
end

# GET — single country (:id cast to Integer automatically)
pais_api.get('/countries/:id', auth: false) do |params|
  c = COUNTRIES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "Not found" } unless c
  c
end

# GET — search by name
pais_api.get('/countries/search', auth: false, requires: [:name]) do |params|
  results = COUNTRIES.select { |c| c[:name].downcase.include?(params[:name].downcase) }
  { total: results.size, countries: results }
end

# POST — create (protected)
pais_api.post('/countries', auth: true, requires: [:name, :capital, :pop]) do |params|
  c = { id: COUNTRIES.size + 1, name: params[:name],
        capital: params[:capital], pop: params[:pop],
        continent: params[:continent] || "Unknown" }
  COUNTRIES << c
  status 201
  { message: "Country created", country: c }
end

# PUT — full replace (protected)
pais_api.put('/countries/:id', auth: true, requires: [:name, :capital]) do |params|
  c = COUNTRIES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "Not found" } unless c
  c[:name] = params[:name]; c[:capital] = params[:capital]
  c[:pop]  = params[:pop] if params[:pop]
  { message: "Updated", country: c }
end

# PATCH — partial update (protected)
pais_api.patch('/countries/:id', auth: true) do |params|
  c = COUNTRIES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "Not found" } unless c
  [:name, :capital, :pop, :continent].each { |k| c[k] = params[k] if params[k] }
  { message: "Patched", country: c }
end

# DELETE (protected)
pais_api.delete('/countries/:id', auth: true) do |params|
  c = COUNTRIES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "Not found" } unless c
  COUNTRIES.delete(c)
  { message: "Deleted", id: params[:id] }
end

# POST — upload flag (multipart, protected)
pais_api.post('/countries/:id/flag', auth: true) do |params|
  file = params[:_files]&.dig(:flag)
  halt 400, { error: 'Field "flag" required' }.to_json unless file
  halt 400, { error: "Format not allowed: #{file.extension}" }.to_json \
    unless %w[.jpg .jpeg .png .svg .webp].include?(file.extension)

  file.save_to("/uploads/flags/#{params[:id]}#{file.extension}")
  status 201
  { message: "Flag uploaded", file: file.to_h }
end

# GET — download flag (public, binary response)
pais_api.get('/countries/:id/flag', auth: false) do |params|
  f = Dir.glob("/uploads/flags/#{params[:id]}.*").first
  halt 404, { error: "Flag not found" }.to_json unless f

  content_type 'application/octet-stream'
  response.headers['Content-Disposition'] = "attachment; filename=\"#{File.basename(f)}\""
  File.binread(f)
end

pais_api.run!
```

```bash
curl http://localhost:4567/geo/v1/countries
curl http://localhost:4567/geo/v1/countries/1
curl -X POST http://localhost:4567/geo/v1/countries \
  -H "Authorization: Bearer geo_secret_2024" \
  -H "Content-Type: application/json" \
  -d '{"name":"Brazil","capital":"Brasilia","pop":215000000}'
curl -X PATCH http://localhost:4567/geo/v1/countries/1 \
  -H "Authorization: Bearer geo_secret_2024" \
  -H "Content-Type: application/json" \
  -d '{"pop":130000000}'
curl -X POST http://localhost:4567/geo/v1/countries/1/flag \
  -H "Authorization: Bearer geo_secret_2024" \
  -F "flag=@mexico_flag.png"
curl -X DELETE http://localhost:4567/geo/v1/countries/3 \
  -H "Authorization: Bearer geo_secret_2024"
```

---

## High Traffic & Concurrency

GR API Manager is built on **Puma** (the standard production Ruby server) and handles concurrent traffic out of the box. Here's how each layer works and what you can tune.

### How it handles concurrency

Puma uses a **multi-worker + multi-thread** model:
- **Workers** = OS processes, each with its own memory. More workers = more CPU cores used.
- **Threads** = lightweight concurrent handlers inside each worker. Threads share memory.

```
Request → Worker 1 → Thread A  →  route handler
                   → Thread B  →  route handler
                   → ...
       → Worker 2 → Thread A  →  route handler
                   → ...
```

A server with `workers: 4, threads: '2:8'` can handle up to **32 simultaneous requests** before queuing.

### Configuring workers and threads

Pass them directly to `run!`:

```ruby
api.run!(
  workers: 4,     # Number of Puma worker processes
  threads: '2:8'  # min_threads:max_threads per worker
)
```

Or via environment variables (recommended for production):

```bash
WEB_CONCURRENCY=4 ruby app.rb
```

**Practical starting points:**

| Scenario | Workers | Threads |
|---|---|---|
| Development / local | 1 | `1:4` |
| Small server (1–2 CPU cores) | 2 | `2:8` |
| Medium server (4 CPU cores) | 4 | `2:8` |
| High-traffic (8+ CPU cores) | 8 | `4:16` |
| I/O-heavy (DB, external APIs) | 2 | `8:32` |

### Built-in rate limiting

Protect your server from flooding and abusive clients with the built-in sliding-window rate limiter:

```ruby
api = GRApiManager::Server.new(
  bearer_token:      "secret",
  rate_limit:        100,   # max 100 requests per IP
  rate_limit_window: 60     # per 60-second window
)
```

When a client exceeds the limit, they receive `429 Too Many Requests`:

```json
{ "error": "Too many requests", "retry_after_seconds": 60 }
```

Response headers are automatically added to every request:

```
X-RateLimit-Limit:     100
X-RateLimit-Remaining: 47
Retry-After:           60   (only on 429 responses)
X-RateLimit-Reset:     1721620800
```

The limiter is **thread-safe** (uses a `Mutex`) and runs a background cleanup thread automatically to prevent memory growth from tracked IPs.

**Common rate limit configs:**

```ruby
# Public API — moderate protection
GRApiManager::Server.new(rate_limit: 200, rate_limit_window: 60)

# Strict — auth endpoints, login, password reset
GRApiManager::Server.new(rate_limit: 10, rate_limit_window: 60)

# Generous — internal service behind a trusted proxy
GRApiManager::Server.new(rate_limit: 2000, rate_limit_window: 60)
```

### Production architecture for truly massive traffic

For thousands of concurrent users, add layers in front of the framework:

```
Internet
   │
   ▼
[Nginx]          ← terminates SSL, serves static files, load balances
   │
   ├──▶ GR API Manager (worker 1, port 4567)
   ├──▶ GR API Manager (worker 2, port 4568)
   └──▶ GR API Manager (worker 3, port 4569)
```

**Minimal Nginx config for load balancing:**

```nginx
upstream gr_api {
    server 127.0.0.1:4567;
    server 127.0.0.1:4568;
    server 127.0.0.1:4569;
}

server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass         http://gr_api;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### What the banner shows

```text
=============================================
  GR API MANAGER STARTED
  Port      : 4567
  Auth      : Enabled
  Prefix    : /api/v1
  Max Body  : 50.0 MB
  Workers   : 4  |  Threads: 2:8
  Rate Limit: 100 req / 60s per IP
  Dev Mode  : Off
=============================================
```

---

## Multiple Route Groups on One Server


You don't need to spin up separate servers for different API sections. Register all your route groups on **a single server instance** — one process, one port, zero extra resource cost.

The cleanest pattern is to extract each group into its own file and pass the server object as an argument:

```
project/
├── main.rb
└── routes/
    ├── users.rb
    ├── countries.rb
    └── products.rb
```

```ruby
# routes/users.rb
def register_users(api)
  api.get('/users', auth: false) do
    { users: [{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }] }
  end

  api.post('/users', auth: true, requires: [:name, :email]) do |params|
    status 201
    { message: "User created", user: { name: params[:name], email: params[:email] } }
  end

  api.delete('/users/:id', auth: true) do |params|
    { message: "User #{params[:id]} deleted" }
  end
end
```

```ruby
# routes/countries.rb
def register_countries(api)
  COUNTRIES = [
    { id: 1, name: "Mexico", capital: "Mexico City" },
    { id: 2, name: "Spain",  capital: "Madrid" }
  ]

  api.get('/countries', auth: false) do
    { total: COUNTRIES.size, countries: COUNTRIES }
  end

  api.get('/countries/:id', auth: false) do |params|
    c = COUNTRIES.find { |x| x[:id] == params[:id] }
    status 404 and next { error: "Not found" } unless c
    c
  end
end
```

```ruby
# routes/products.rb
def register_products(api)
  api.get('/products', auth: false) do
    { products: [{ id: 1, name: "Laptop", price: 999.99 }] }
  end

  api.post('/products', auth: true, requires: [:name, :price]) do |params|
    status 201
    { message: "Product created", product: { name: params[:name], price: params[:price] } }
  end
end
```

```ruby
# main.rb — one server, three route groups, one process
require 'gr_api_manager'
require_relative 'routes/users'
require_relative 'routes/countries'
require_relative 'routes/products'

api = GRApiManager::Server.new(
  port:         4567,
  bearer_token: "secret",
  prefix:       "/api/v1"
)

register_users(api)       # mounts: GET/POST /api/v1/users, DELETE /api/v1/users/:id
register_countries(api)   # mounts: GET /api/v1/countries, GET /api/v1/countries/:id
register_products(api)    # mounts: GET/POST /api/v1/products

api.run!
# All routes available on a single process at localhost:4567
```

```bash
# All three groups work on the same server
curl http://localhost:4567/api/v1/users
curl http://localhost:4567/api/v1/countries
curl http://localhost:4567/api/v1/products

curl -X POST http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: application/json" \
  -d '{"name":"Carlos","email":"carlos@example.com"}'
```

This approach scales cleanly — add new route groups without touching `main.rb` logic, and everything shares the same auth token, prefix, and body size limit.

---

## License

Available as open source under the [MIT License](https://opensource.org/licenses/MIT).
