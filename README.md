# GR API Manager

[![Gem Version](https://badge.fury.io/rb/gr-api-manager.svg)](https://rubygems.org/gems/gr-api-manager)

A minimal, opinionated Ruby wrapper around Sinatra that eliminates boilerplate from REST API development. Authentication, parameter validation, type casting, CORS, and error handling are handled at the framework level — you write only the business logic.

---

## Features

- **Available on RubyGems!** Install globally and use it in any project.
- Route-level Bearer Token authentication (opt-in/opt-out per endpoint).
- Declarative required parameter validation with automatic `400 Bad Request` responses.
- Smart type casting for query string values (`"10"` -> `Integer`, `"true"` -> `TrueClass`, `"9.5"` -> `Float`).
- Global JSON error responses for `404` and `500`.
- Broad CORS and `OPTIONS` preflight handling out of the box (Frontend ready).
- API versioning via configurable route prefix (e.g. `/api/v1`).

---

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'gr-api-manager'
```

And then execute:
```bash
bundle install
```

Or install it yourself directly via RubyGems:
```bash
gem install gr-api-manager
```

---

## Quick Start

```ruby
require 'gr_api_manager'

api = GRApiManager::Server.new(
  port: 4567,
  bearer_token: "your_secret_token",
  prefix: "/api/v1"
)

# Public endpoint
api.get('/health', auth: false) do
  { status: 'online', time: Time.now.to_s }
end

api.run!
```

```bash
curl http://localhost:4567/api/v1/health
# => {"status":"online","time":"..."}
```

---

## Configuration

All parameters are optional. If omitted, the manager falls back to environment variables loaded from a `.env` file at the project root (via `dotenv`). If neither is provided, defaults are used.

```ruby
GRApiManager::Server.new(
  port: 4567,                        # Default: ENV['PORT'] || 4000
  bearer_token: "secret",            # Default: ENV['API_TOKEN']
  permitted_hosts: ["example.com"],  # Host allowlist — empty means allow all
  prefix: "/api/v1"                  # Route prefix applied to all endpoints
)
```

### Using a .env file (Recommended)

Create a `.env` file at the root of your project:

```env
PORT=4567
API_TOKEN=your_secret_token
```

Then initialize the manager with no arguments and it will pick everything up automatically:

```ruby
require 'gr_api_manager'

api = GRApiManager::Server.new
# Reads PORT and API_TOKEN from .env
```

This is the recommended approach for production — keep secrets out of source code and out of version control. Add `.env` to your `.gitignore`.

```text
# .gitignore
.env
```

### Priority order

When a value is provided both in code and in `.env`, the explicit argument always wins:

```text
new(bearer_token: "hardcoded")  >  ENV['API_TOKEN']  >  nil (auth disabled)
new(port: 4567)                 >  ENV['PORT']        >  4000
```

---

## Defining Routes

The manager exposes `get`, `post`, `put`, and `delete` methods. Each route receives a merged `params` hash containing both URL/query parameters (type-cast) and the parsed JSON body.

```ruby
api.get('/users', auth: true, requires: [:role, :age]) do |params|
  # params is a merged, type-cast hash of all inputs
  { 
    requested_role: params[:role],
    is_adult: params[:age] >= 18 # age is safely cast to Integer
  }
end
```

### Options

| Option     | Type    | Default | Description                                      |
|------------|---------|---------|--------------------------------------------------|
| `auth`     | Boolean | `true`  | Require Bearer Token for this route              |
| `requires` | Array   | `[]`    | List of required parameter keys (symbols/strings)|

---

## Authentication

All routes require a valid Bearer Token by default. Pass the token in the `Authorization` header:

```bash
curl -H "Authorization: Bearer your_secret_token" http://localhost:4567/api/v1/users
```

To make a route public, set `auth: false`:

```ruby
api.get('/health', auth: false) do
  { status: 'online' }
end
```

**Automatic Error Responses:**

```json
// Missing header (401)
{ "error": "Token required. Format: 'Bearer <token>'" }

// Wrong token (403)
{ "error": "Invalid token" }
```

---

## Parameter Validation

Declare required parameters at the route level. If any are missing or blank, the framework responds with `400 Bad Request` automatically — no conditional logic needed in your handler.

```ruby
api.post('/users', requires: [:name, :email]) do |params|
  status 201
  { message: "User created", user: params }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: application/json" \
  -d '{"name": "Gabo"}'

# => 400 { "error": "Missing required parameters", "required": ["email"] }
```

---

## Smart Type Casting

Query string parameters are automatically cast to native Ruby types before reaching your handler.

| Input string | Ruby type | Value    |
|--------------|-----------|----------|
| `"42"`       | Integer   | `42`     |
| `"3.14"`     | Float     | `3.14`   |
| `"true"`     | TrueClass | `true`   |
| `"false"`    | FalseClass| `false`  |
| `"hello"`    | String    | `"hello"`|

```bash
curl "http://localhost:4567/api/v1/test/types?age=18&active=true&score=9.5" \
  -H "Authorization: Bearer secret"

# => { "age": 18, "active": true, "score": 9.5 }
```

---

## Error Handling

Global handlers return consistent JSON for unmatched routes and unhandled exceptions.

```json
// 404
{ "error": "Endpoint not found", "path": "/api/v1/missing" }

// 500
{ "error": "Internal Server Error", "details": "..." }
```

You can also set status codes and short-circuit responses manually inside any handler:

```ruby
api.get('/users/:id') do |params|
  if params[:id] == 0
    status 404
    next { error: "Invalid user ID" }
  end

  { id: params[:id], name: "User_#{params[:id]}" }
end
```

---

## Request Logging

Every request is logged to stdout with a timestamp and color-coded status:

```text
[14:32:01] GET /api/v1/health - 200
[14:32:05] POST /api/v1/users - 400
```

Green for 2xx, red for everything else.

---

## Running the Server

```ruby
api.run!
```

```text
=============================================
  GR API MANAGER STARTED
  Port   : 4567
  Auth   : Enabled
  Prefix : /api/v1
=============================================
```

---

## Full Usage Example

Below is a complete working API covering the most common patterns.

```ruby
require 'gr_api_manager'

api = GRApiManager::Server.new(
  port: 4567,
  bearer_token: "secret123",
  prefix: "/api/v1"
)

# 1. Public health check — no token required
api.get('/health', auth: false) do
  { status: 'online', time: Time.now.strftime("%Y-%m-%d %H:%M:%S") }
end

# 2. List users — token required (default)
api.get('/users') do |params|
  users = [
    { id: 1, name: "Alice", role: "admin" },
    { id: 2, name: "Bob",   role: "viewer" }
  ]
  { users: users, total: users.length }
end

# 3. Get single user by ID — :id is cast to Integer automatically
api.get('/users/:id') do |params|
  if params[:id] == 0
    status 404
    next { error: "User not found" }
  end
  { id: params[:id], name: "User_#{params[:id]}" }
end

# 4. Create user — validates required fields before reaching the block
api.post('/users', requires: [:name, :role]) do |params|
  status 201
  { message: "User created", user: { name: params[:name], role: params[:role] } }
end

# 5. Update user
api.put('/users/:id', requires: [:name]) do |params|
  { message: "User #{params[:id]} updated", name: params[:name] }
end

# 6. Delete user
api.delete('/users/:id') do |params|
  { message: "User #{params[:id]} deleted" }
end

api.run!
```

### Minimal setup using only .env

```env
# .env
PORT=4567
API_TOKEN=secret123
```

```ruby
# api_server.rb
require 'gr_api_manager'

api = GRApiManager::Server.new  # reads everything from .env

api.get('/ping', auth: false) { { pong: true } }

api.run!
```

---

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
