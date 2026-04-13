# Sinatra API Manager

A minimal, opinionated Ruby wrapper around Sinatra that eliminates boilerplate from REST API development. Authentication, parameter validation, type casting, CORS, and error handling are handled at the framework level — you write only business logic.

---

## Features

- Route-level Bearer Token authentication (opt-in/opt-out per endpoint)
- Declarative required parameter validation with automatic 400 responses
- Smart type casting for query string values (`"10"` → `Integer`, `"true"` → `TrueClass`, `"9.5"` → `Float`)
- Global JSON error responses for 404 and 500
- CORS and OPTIONS preflight handling out of the box
- API versioning via configurable route prefix (e.g. `/api/v1`)
- Automatic JSON serialization of all responses

---

## Requirements

- Ruby 3.x
- `sinatra`
- `dotenv`

```bash
gem install sinatra dotenv
```

---

## Quick Start

```ruby
require_relative 'api'

api = ApiManager::NewApi.new(
  port: 4567,
  bearer_token: "your_secret_token",
  prefix: "/api/v1"
)

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
ApiManager::NewApi.new(
  port: 4567,                        # Default: ENV['PORT'] || 4000
  bearer_token: "secret",            # Default: ENV['API_TOKEN']
  permitted_hosts: ["example.com"],  # Host allowlist — empty means allow all
  prefix: "/api/v1"                  # Route prefix applied to all endpoints
)
```

### Using a .env file

Create a `.env` file at the root of your project:

```env
PORT=4567
API_TOKEN=your_secret_token
```

Then initialize the manager with no arguments and it will pick everything up automatically:

```ruby
api = ApiManager::NewApi.new
# Reads PORT and API_TOKEN from .env
```

This is the recommended approach for production — keep secrets out of source code and out of version control. Add `.env` to your `.gitignore`.

```
# .gitignore
.env
```

### Priority order

When a value is provided both in code and in `.env`, the explicit argument always wins:

```
new(bearer_token: "hardcoded")  >  ENV['API_TOKEN']  >  nil (auth disabled)
new(port: 4567)                 >  ENV['PORT']        >  4000
```

---

## Defining Routes

The manager exposes `get`, `post`, `put`, and `delete` methods. Each route receives a merged `params` hash containing both URL/query parameters (type-cast) and the parsed JSON body.

```ruby
api.get('/path', auth: true, requires: [:param1, :param2]) do |params|
  # params is a merged, type-cast hash of all inputs
  { result: params[:param1] }
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

Error responses:

```json
// Missing header
{ "error": "Token requerido. Formato: 'Bearer <token>'" }  // 401

// Wrong token
{ "error": "Token inválido" }  // 403
```

---

## Parameter Validation

Declare required parameters at the route level. If any are missing or blank, the framework responds with `400` automatically — no conditional logic needed in your handler.

```ruby
api.post('/users', requires: [:name, :role]) do |params|
  status 201
  { message: "Created", user: params }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret" \
  -H "Content-Type: application/json" \
  -d '{"name": "Gabo"}'

# => 400 { "error": "Faltan parámetros obligatorios", "required": ["role"] }
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
{ "error": "Endpoint no encontrado", "path": "/api/v1/missing" }

// 500
{ "error": "Error interno del servidor", "details": "..." }
```

You can also set status codes and short-circuit responses manually inside any handler:

```ruby
api.get('/users/:id') do |params|
  if params[:id] == 0
    status 404
    next { error: "ID de usuario no válido" }
  end

  { id: params[:id], name: "User_#{params[:id]}" }
end
```

---

## Request Logging

Every request is logged to stdout with a timestamp and color-coded status:

```
[14:32:01] GET /api/v1/health - 200
[14:32:05] POST /api/v1/users - 400
```

Green for 2xx, red for everything else.

---

## Running the Server

```ruby
api.run!
```

```
=============================================
API MANAGER INICIADO
Puerto : 4567
Auth   : Requerida por defecto
Prefix : /api/v1
=============================================
```

---

## Project Structure

```
sinatra_manager/
├── api.rb        # Core framework — ApiManager::NewApi
├── ejemplos.rb   # Usage examples and test routes
├── .env          # PORT and API_TOKEN (not committed)
└── README.md
```

---

## Full Usage Example

Below is a complete working API covering the most common patterns.

```ruby
require_relative 'api'

api = ApiManager::NewApi.new(
  port: 4567,
  bearer_token: "secret123",
  prefix: "/api/v1"
)

# Public health check — no token required
api.get('/health', auth: false) do
  { status: 'online', time: Time.now.strftime("%Y-%m-%d %H:%M:%S") }
end

# List users — token required (default)
api.get('/users') do |params|
  users = [
    { id: 1, name: "Alice", role: "admin" },
    { id: 2, name: "Bob",   role: "viewer" }
  ]
  { users: users, total: users.length }
end

# Get single user by ID — :id is cast to Integer automatically
api.get('/users/:id') do |params|
  if params[:id] == 0
    status 404
    next { error: "User not found" }
  end
  { id: params[:id], name: "User_#{params[:id]}" }
end

# Create user — validates required fields before reaching the block
api.post('/users', requires: [:name, :role]) do |params|
  status 201
  { message: "User created", user: { name: params[:name], role: params[:role] } }
end

# Update user
api.put('/users/:id', requires: [:name]) do |params|
  { message: "User #{params[:id]} updated", name: params[:name] }
end

# Delete user
api.delete('/users/:id') do |params|
  { message: "User #{params[:id]} deleted" }
end

api.run!
```

### Calling the API

```bash
# Health check (no auth)
curl http://localhost:4567/api/v1/health

# List users
curl http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret123"

# Get user by ID
curl http://localhost:4567/api/v1/users/42 \
  -H "Authorization: Bearer secret123"

# Create user
curl -X POST http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret123" \
  -H "Content-Type: application/json" \
  -d '{"name": "Gabo", "role": "admin"}'

# Create user — missing 'role' triggers automatic 400
curl -X POST http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer secret123" \
  -H "Content-Type: application/json" \
  -d '{"name": "Gabo"}'
# => {"error":"Faltan parámetros obligatorios","required":["role"]}

# Update user
curl -X PUT http://localhost:4567/api/v1/users/42 \
  -H "Authorization: Bearer secret123" \
  -H "Content-Type: application/json" \
  -d '{"name": "Gabo Updated"}'

# Delete user
curl -X DELETE http://localhost:4567/api/v1/users/42 \
  -H "Authorization: Bearer secret123"

# Wrong token — returns 403
curl http://localhost:4567/api/v1/users \
  -H "Authorization: Bearer wrongtoken"
# => {"error":"Token inválido"}

# Missing token — returns 401
curl http://localhost:4567/api/v1/users
# => {"error":"Token requerido. Formato: 'Bearer <token>'"}
```

### Minimal setup using only .env

```env
# .env
PORT=4567
API_TOKEN=secret123
```

```ruby
# api_server.rb
require_relative 'api'

api = ApiManager::NewApi.new  # reads everything from .env

api.get('/ping', auth: false) { { pong: true } }

api.run!
```

---

## License

MIT
