# GR API Manager

[![Gem Version](https://badge.fury.io/rb/gr-api-manager.svg)](https://rubygems.org/gems/gr-api-manager)
[![README in English](https://img.shields.io/badge/README-English-blue)](README.md)

Un wrapper minimalista de Ruby sobre Sinatra que elimina el boilerplate del desarrollo de APIs REST. Auth, validación de parámetros, cast de tipos, CORS, manejo de errores, **uploads de archivos, binarios crudos, imágenes, Base64 y hexadecimal** — todo a nivel de framework. Tú solo escribes la lógica de negocio.

---

## Características

- Disponible en **RubyGems** — instálalo globalmente y úsalo en cualquier proyecto.
- Autenticación Bearer Token por ruta (activable/desactivable por endpoint).
- Validación declarativa de parámetros requeridos → `400 Bad Request` automático.
- Cast inteligente de tipos: `"10"` → `Integer`, `"true"` → `TrueClass`, `"9.5"` → `Float`.
- Respuestas JSON globales para `404`, `500` y `413`.
- CORS amplio y preflight `OPTIONS` listo de fábrica.
- Versionado de API mediante prefijo configurable (`/api/v1`, `/geo/v2`, etc.).
- **Soporte completo de archivos y binarios** — multipart, binarios crudos, Base64, hex, `text/plain`.
- Límite de tamaño de body configurable con helpers `mb` / `gb`.
- **Dev mode** — stack traces completos en errores `500` para facilitar la depuración.

---

## Instalación

```ruby
gem 'gr-api-manager'   # Gemfile
```

```bash
bundle install
# o: gem install gr-api-manager
```

---

## Inicio rápido — ponle el nombre que quieras

El objeto `Server` es simplemente un objeto Ruby. Llámalo `api`, `app`, `pais_api`, `backend`, `mi_servicio` — como mejor le quede a tu proyecto. No hay nombre mágico obligatorio.

```ruby
require 'gr_api_manager'

# Cualquier nombre funciona
api      = GRApiManager::Server.new(port: 4567, bearer_token: "secreto")
pais_api = GRApiManager::Server.new(prefix: "/geo/v1")
reportes = GRApiManager::Server.new(port: 5000, max_body_size: GRApiManager.gb(1))

api.get('/health', auth: false) { { status: 'ok' } }
api.run!
```

---

## Configuración

```ruby
GRApiManager::Server.new(
  port:            4567,
  bearer_token:    "secreto",
  permitted_hosts: ["example.com"],   # vacío = permitir todos
  prefix:          "/api/v1",
  max_body_size:   GRApiManager.mb(50),  # default 50 MB
  dev_mode:        false                 # default false
)
```

### Helpers de tamaño

Expresa los límites sin hacer cálculos manuales:

```ruby
GRApiManager.mb(50)    # 50 megabytes
GRApiManager.mb(200)   # 200 megabytes — para uploads grandes
GRApiManager.gb(1)     # 1 gigabyte   — para reportes o video pesado

# Ejemplos reales
video_api  = GRApiManager::Server.new(max_body_size: GRApiManager.gb(2))
json_api   = GRApiManager::Server.new(max_body_size: GRApiManager.mb(1))
reporte_api = GRApiManager::Server.new(max_body_size: GRApiManager.mb(500))
```

### Archivo `.env` (recomendado en producción)

```env
PORT=4567
API_TOKEN=tu_token_secreto
```

```ruby
api = GRApiManager::Server.new   # lee PORT y API_TOKEN automáticamente
```

Los argumentos explícitos siempre tienen prioridad sobre `.env`. Agrega `.env` a `.gitignore`.

---

## Verbos HTTP — qué hace cada uno

| Método | Propósito | Uso típico |
|---|---|---|
| `GET` | **Leer** — obtener datos, sin efectos secundarios | Listar, buscar, obtener por ID |
| `POST` | **Crear** — agregar un nuevo recurso | Crear usuario, subir archivo |
| `PUT` | **Reemplazar** — reemplaza un recurso existente por completo | Actualizar perfil completo |
| `PATCH` | **Actualización parcial** — modificar campos específicos | Cambiar solo el email |
| `DELETE` | **Eliminar** — borrar un recurso | Eliminar usuario, borrar archivo |

```ruby
api.get('/usuarios')         { ... }   # listar
api.get('/usuarios/:id')     { ... }   # leer uno
api.post('/usuarios')        { ... }   # crear
api.put('/usuarios/:id')     { ... }   # reemplazar completo
api.patch('/usuarios/:id')   { ... }   # actualización parcial
api.delete('/usuarios/:id')  { ... }   # eliminar
```

---

## Definiendo rutas

```ruby
api.post('/ruta', auth: true, requires: [:nombre, :email]) do |params|
  # params — hash unificado: segmentos URL + query string (con cast) + body parseado
  { resultado: "ok" }
end
```

| Opción | Tipo | Default | Descripción |
|---|---|---|---|
| `auth` | Boolean | `true` | Requerir Bearer Token |
| `requires` | Array | `[]` | Parámetros requeridos |

---

## Respuestas exitosas

Retorna cualquier Hash o Array — el framework lo serializa a JSON automáticamente.

```ruby
# Hash simple
api.get('/ping', auth: false) { { pong: true } }

# Con código de status
api.post('/usuarios', requires: [:nombre]) do |params|
  status 201
  { mensaje: "Creado", usuario: { nombre: params[:nombre] } }
end

# Cortocircuito con next
api.get('/usuarios/:id') do |params|
  if params[:id] == 0
    status 404
    next { error: "No encontrado" }
  end
  { id: params[:id], nombre: "Alice" }
end
```

> Si retornas un `String` (ej. datos binarios), el framework lo envía **tal cual** sin envolver en JSON. Útil para servir archivos.

---

## Autenticación

```ruby
api.get('/health', auth: false) { { status: 'online' } }  # pública

api.get('/datos') do |params|    # protegida (default)
  { secreto: "datos" }
end
```

```bash
curl -H "Authorization: Bearer tu_token" http://localhost:4567/api/v1/datos
```

```json
// 401 — header faltante
{ "error": "Token required. Format: 'Bearer <token>'" }

// 403 — token incorrecto
{ "error": "Invalid token" }
```

---

## Validación de parámetros

```ruby
api.post('/usuarios', requires: [:nombre, :email, :rol]) do |params|
  status 201
  { mensaje: "Usuario creado", usuario: params }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/usuarios \
  -H "Authorization: Bearer secreto" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Gabo"}'

# => 400 { "error": "Missing required parameters", "required": ["email", "rol"] }
```

---

## Cast inteligente de tipos

Los parámetros query string se convierten automáticamente antes de llegar a tu bloque:

| String | Tipo Ruby | Valor |
|---|---|---|
| `"42"` | Integer | `42` |
| `"3.14"` | Float | `3.14` |
| `"true"` | TrueClass | `true` |
| `"false"` | FalseClass | `false` |

```bash
curl "http://localhost:4567/api/v1/productos?pagina=2&activo=true&precio=9.99"
# params => { pagina: 2, activo: true, precio: 9.99 }
```

---

## Manejo de archivos y binarios

El framework detecta el `Content-Type` automáticamente y parsea el body. **Sin configuración extra.**

### Formatos soportados

| Content-Type | Qué recibes en `params` |
|---|---|
| `application/json` | Hash normal con claves simbolizadas |
| `multipart/form-data` | Campos de texto + `:_files` → `{ campo: FilePayload }` |
| `image/*`, `video/*`, `audio/*` | `:_raw_binary` → `FilePayload` |
| `application/pdf`, `application/msword`, `application/vnd.*` | `:_raw_binary` → `FilePayload` |
| `application/octet-stream` | `:_raw_binary` → `FilePayload` |
| `text/plain` | `:_raw_text` → `String` |

### API de `FilePayload`

| Método | Retorna | Descripción |
|---|---|---|
| `#read` | `String` (binario) | Bytes crudos |
| `#to_base64` | `String` | Contenido en Base64 (sin saltos de línea) |
| `#to_hex` | `String` | Cadena hexadecimal en minúsculas |
| `#save_to(ruta)` | `String` | Guarda en disco, retorna la ruta |
| `#filename` | `String` | Nombre original del archivo |
| `#content_type` | `String` | Tipo MIME |
| `#size` | `Integer` | Tamaño en bytes |
| `#extension` | `String` | Extensión (`.jpg`, `.pdf`, etc.) |
| `#to_h` | `Hash` | Resumen seguro para JSON |

### Subir una imagen con multipart

```ruby
api.post('/upload/avatar', auth: true) do |params|
  file = params[:_files][:avatar]
  halt 400, { error: 'Campo "avatar" requerido' }.to_json unless file
  halt 400, { error: "Tipo no permitido" }.to_json unless %w[.jpg .png .webp].include?(file.extension)

  file.save_to("/uploads/#{file.filename}")
  status 201
  { mensaje: "Subido", archivo: file.to_h }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/upload/avatar \
  -H "Authorization: Bearer secreto" \
  -F "avatar=@foto.jpg"
```

### Múltiples archivos en una sola petición

```ruby
api.post('/documentos', auth: true) do |params|
  archivos = params[:_files] || {}
  halt 400, { error: 'No se recibió ningún archivo' }.to_json if archivos.empty?

  guardados = archivos.map { |_, f| f.save_to("/uploads/#{f.filename}"); f.to_h }
  status 201
  { subidos: guardados }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/documentos \
  -H "Authorization: Bearer secreto" \
  -F "doc=@reporte.pdf" -F "thumbnail=@miniatura.png"
```

### Body binario crudo (imagen, PDF, Word, etc.)

```ruby
api.post('/archivos/raw', auth: true) do |params|
  file = params[:_raw_binary]
  halt 400, { error: 'Body binario requerido' }.to_json unless file

  ruta = file.save_to("/uploads/#{file.filename}")
  { guardado_en: ruta, magic_bytes: file.to_hex[0, 8], bytes: file.size }
end
```

```bash
curl -X POST http://localhost:4567/api/v1/archivos/raw \
  -H "Authorization: Bearer secreto" \
  -H "Content-Type: image/png" --data-binary @foto.png

curl -X POST http://localhost:4567/api/v1/archivos/raw \
  -H "Authorization: Bearer secreto" \
  -H "Content-Type: application/pdf" --data-binary @doc.pdf
```

### Base64 dentro de JSON

```ruby
require 'base64'

api.post('/archivos/base64', auth: true, requires: [:data, :filename]) do |params|
  raw  = Base64.strict_decode64(params[:data])
  File.open("/uploads/#{params[:filename]}", 'wb') { |f| f.write(raw) }
  { mensaje: "Guardado", bytes: raw.bytesize }
end
```

```bash
BASE64=$(base64 -w0 foto.jpg)
curl -X POST http://localhost:4567/api/v1/archivos/base64 \
  -H "Authorization: Bearer secreto" \
  -H "Content-Type: application/json" \
  -d "{\"filename\":\"foto.jpg\",\"data\":\"$BASE64\"}"
```

### Hexadecimal

```ruby
api.post('/archivos/tohex', auth: true) do |params|
  file = params[:_raw_binary]
  halt 400, { error: 'Body binario requerido' }.to_json unless file
  # to_hex convierte cualquier binario a string hexadecimal en minúsculas
  { hex: file.to_hex, bytes: file.size }
end
```

### Cuerpo de texto plano

```ruby
api.post('/notas', auth: true) do |params|
  texto = params[:_raw_text]
  halt 400, { error: 'Body vacío' }.to_json if texto.nil? || texto.strip.empty?
  { recibido: texto, palabras: texto.split.size }
end
```

### Servir un archivo como respuesta binaria

```ruby
api.get('/archivos/:nombre', auth: true) do |params|
  ruta = "/uploads/#{File.basename(params[:nombre].to_s)}"
  halt 404, { error: "No encontrado" }.to_json unless File.exist?(ruta)

  content_type 'application/octet-stream'
  response.headers['Content-Disposition'] = "attachment; filename=\"#{File.basename(ruta)}\""
  File.binread(ruta)   # String → se manda tal cual, sin envolver en JSON
end
```

### Límite de tamaño del body

```json
// Cuando se supera → 413
{ "error": "Payload too large", "max_bytes": 52428800 }
```

```ruby
GRApiManager::Server.new(max_body_size: GRApiManager.mb(200))  # 200 MB
GRApiManager::Server.new(max_body_size: GRApiManager.gb(2))    # 2 GB
GRApiManager::Server.new(max_body_size: GRApiManager.mb(1))    # 1 MB
```

---

## Modo Dev

Actívalo durante el desarrollo para obtener stack traces completos en errores `500`:

```ruby
api = GRApiManager::Server.new(
  bearer_token: "secreto",
  dev_mode: true   # ⚠️ Nunca activar en producción
)
```

**Producción (dev_mode: false):**
```json
{ "error": "Internal Server Error", "details": "undefined method 'foo' for nil" }
```

**Desarrollo (dev_mode: true):**
```json
{
  "error": "Internal Server Error",
  "details": "undefined method 'foo' for nil",
  "class": "NoMethodError",
  "backtrace": ["app.rb:42:in 'block in register_route'", "..."]
}
```

---

## Manejo de errores

```json
// 404
{ "error": "Endpoint not found", "path": "/api/v1/ruta-inexistente" }

// 500
{ "error": "Internal Server Error", "details": "..." }

// 413
{ "error": "Payload too large", "max_bytes": 52428800 }
```

---

## Log de peticiones

```text
[14:32:01] GET  /api/v1/health - 200
[14:32:05] POST /api/v1/usuarios - 400
[14:32:10] POST /api/v1/upload/avatar - 201
```

Verde para 2xx, rojo para todo lo demás.

---

## Iniciando el servidor

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

## Ejemplo completo — API de Países

Este ejemplo muestra cómo el framework maneja un CRUD real con uploads de archivos. El servidor se llama `pais_api` — **el nombre es completamente tuyo**.

```ruby
require 'gr_api_manager'
require 'fileutils'

FileUtils.mkdir_p('/uploads/banderas')

pais_api = GRApiManager::Server.new(
  port:          4567,
  bearer_token:  "geo_secreto_2024",
  prefix:        "/geo/v1",
  max_body_size: GRApiManager.mb(5),
  dev_mode:      true
)

PAISES = [
  { id: 1, nombre: "México",    capital: "Ciudad de México", pob: 128_000_000, continente: "América del Norte" },
  { id: 2, nombre: "Argentina", capital: "Buenos Aires",     pob: 45_000_000,  continente: "América del Sur" },
  { id: 3, nombre: "España",    capital: "Madrid",           pob: 47_000_000,  continente: "Europa" }
]

# GET — listar todos (público)
pais_api.get('/paises', auth: false) do
  { total: PAISES.size, paises: PAISES }
end

# GET — obtener uno (:id se convierte a Integer automáticamente)
pais_api.get('/paises/:id', auth: false) do |params|
  p = PAISES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "No encontrado" } unless p
  p
end

# GET — buscar por nombre
pais_api.get('/paises/buscar', auth: false, requires: [:nombre]) do |params|
  resultados = PAISES.select { |p| p[:nombre].downcase.include?(params[:nombre].downcase) }
  { total: resultados.size, paises: resultados }
end

# POST — crear (protegido)
pais_api.post('/paises', auth: true, requires: [:nombre, :capital, :pob]) do |params|
  nuevo = { id: PAISES.size + 1, nombre: params[:nombre],
            capital: params[:capital], pob: params[:pob],
            continente: params[:continente] || "Desconocido" }
  PAISES << nuevo
  status 201
  { mensaje: "País creado", pais: nuevo }
end

# PUT — reemplazar completo (protegido)
pais_api.put('/paises/:id', auth: true, requires: [:nombre, :capital]) do |params|
  p = PAISES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "No encontrado" } unless p
  p[:nombre] = params[:nombre]; p[:capital] = params[:capital]
  p[:pob]    = params[:pob] if params[:pob]
  { mensaje: "Actualizado", pais: p }
end

# PATCH — actualización parcial (protegido)
pais_api.patch('/paises/:id', auth: true) do |params|
  p = PAISES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "No encontrado" } unless p
  [:nombre, :capital, :pob, :continente].each { |k| p[k] = params[k] if params[k] }
  { mensaje: "Parcialmente actualizado", pais: p }
end

# DELETE (protegido)
pais_api.delete('/paises/:id', auth: true) do |params|
  p = PAISES.find { |x| x[:id] == params[:id] }
  status 404 and next { error: "No encontrado" } unless p
  PAISES.delete(p)
  { mensaje: "Eliminado", id: params[:id] }
end

# POST — subir bandera (multipart, protegido)
pais_api.post('/paises/:id/bandera', auth: true) do |params|
  archivo = params[:_files]&.dig(:bandera)
  halt 400, { error: 'Campo "bandera" requerido' }.to_json unless archivo
  halt 400, { error: "Formato no permitido: #{archivo.extension}" }.to_json \
    unless %w[.jpg .jpeg .png .svg .webp].include?(archivo.extension)

  archivo.save_to("/uploads/banderas/#{params[:id]}#{archivo.extension}")
  status 201
  { mensaje: "Bandera subida", archivo: archivo.to_h }
end

# GET — descargar bandera (público, respuesta binaria)
pais_api.get('/paises/:id/bandera', auth: false) do |params|
  f = Dir.glob("/uploads/banderas/#{params[:id]}.*").first
  halt 404, { error: "Bandera no encontrada" }.to_json unless f

  content_type 'application/octet-stream'
  response.headers['Content-Disposition'] = "attachment; filename=\"#{File.basename(f)}\""
  File.binread(f)
end

pais_api.run!
```

```bash
curl http://localhost:4567/geo/v1/paises
curl http://localhost:4567/geo/v1/paises/1
curl -X POST http://localhost:4567/geo/v1/paises \
  -H "Authorization: Bearer geo_secreto_2024" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Brasil","capital":"Brasilia","pob":215000000}'
curl -X PATCH http://localhost:4567/geo/v1/paises/1 \
  -H "Authorization: Bearer geo_secreto_2024" \
  -H "Content-Type: application/json" \
  -d '{"pob":130000000}'
curl -X POST http://localhost:4567/geo/v1/paises/1/bandera \
  -H "Authorization: Bearer geo_secreto_2024" \
  -F "bandera=@bandera_mexico.png"
curl -X DELETE http://localhost:4567/geo/v1/paises/3 \
  -H "Authorization: Bearer geo_secreto_2024"
```

---

## Tráfico masivo y concurrencia

GR API Manager está construido sobre **Puma** (el servidor Ruby estándar para producción) y maneja tráfico concurrente de fábrica. Así funciona cada capa y qué puedes ajustar.

### Cómo maneja la concurrencia

Puma usa un modelo **multi-worker + multi-thread**:
- **Workers** = procesos del SO, cada uno con su propia memoria. Más workers = más núcleos de CPU usados.
- **Threads** = hilos ligeros dentro de cada worker. Comparten memoria.

```
Petición → Worker 1 → Hilo A  →  handler de ruta
                    → Hilo B  →  handler de ruta
                    → ...
         → Worker 2 → Hilo A  →  handler de ruta
                    → ...
```

Un servidor con `workers: 4, threads: '2:8'` puede manejar hasta **32 peticiones simultáneas** antes de encolar.

### Configurar workers y threads

Pásalos directamente a `run!`:

```ruby
api.run!(
  workers: 4,     # Procesos worker de Puma
  threads: '2:8'  # min_threads:max_threads por worker
)
```

O vía variables de entorno (recomendado en producción):

```bash
WEB_CONCURRENCY=4 ruby app.rb
```

**Puntos de partida prácticos:**

| Escenario | Workers | Threads |
|---|---|---|
| Desarrollo / local | 1 | `1:4` |
| Servidor pequeño (1–2 núcleos) | 2 | `2:8` |
| Servidor mediano (4 núcleos) | 4 | `2:8` |
| Alto tráfico (8+ núcleos) | 8 | `4:16` |
| I/O intensivo (BD, APIs externas) | 2 | `8:32` |

### Rate limiting integrado

Protege tu servidor de flooding y clientes abusivos con el rate limiter de ventana deslizante incluido:

```ruby
api = GRApiManager::Server.new(
  bearer_token:      "secreto",
  rate_limit:        100,   # máx 100 peticiones por IP
  rate_limit_window: 60     # por ventana de 60 segundos
)
```

Cuando un cliente supera el límite recibe `429 Too Many Requests`:

```json
{ "error": "Too many requests", "retry_after_seconds": 60 }
```

Los headers se agregan automáticamente a cada petición:

```
X-RateLimit-Limit:     100
X-RateLimit-Remaining: 47
Retry-After:           60   (solo en respuestas 429)
X-RateLimit-Reset:     1721620800
```

El limiter es **thread-safe** (usa un `Mutex`) y corre un hilo de limpieza en segundo plano para evitar crecimiento de memoria con IPs rastreadas.

**Configuraciones comunes:**

```ruby
# API pública — protección moderada
GRApiManager::Server.new(rate_limit: 200, rate_limit_window: 60)

# Estricto — endpoints de auth, login, recuperación de contraseña
GRApiManager::Server.new(rate_limit: 10, rate_limit_window: 60)

# Generoso — servicio interno detrás de un proxy confiable
GRApiManager::Server.new(rate_limit: 2000, rate_limit_window: 60)
```

### Arquitectura de producción para tráfico verdaderamente masivo

Para miles de usuarios concurrentes, agrega capas frente al framework:

```
Internet
   │
   ▼
[Nginx]          ← termina SSL, sirve archivos estáticos, balancea carga
   │
   ├──▶ GR API Manager (worker 1, puerto 4567)
   ├──▶ GR API Manager (worker 2, puerto 4568)
   └──▶ GR API Manager (worker 3, puerto 4569)
```

**Config mínima de Nginx para balanceo:**

```nginx
upstream gr_api {
    server 127.0.0.1:4567;
    server 127.0.0.1:4568;
    server 127.0.0.1:4569;
}

server {
    listen 80;
    server_name api.tudominio.com;

    location / {
        proxy_pass         http://gr_api;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### Qué muestra el banner

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

## Múltiples grupos de rutas en un solo servidor


No necesitas levantar servidores separados para distintas secciones de tu API. Registra todos tus grupos de rutas en **una sola instancia de servidor** — un proceso, un puerto, cero costo extra de recursos.

El patrón más limpio es extraer cada grupo en su propio archivo y pasar el objeto servidor como argumento:

```
proyecto/
├── main.rb
└── rutas/
    ├── usuarios.rb
    ├── paises.rb
    └── productos.rb
```

```ruby
# rutas/usuarios.rb
def registrar_usuarios(api)
  api.get('/usuarios', auth: false) do
    { usuarios: [{ id: 1, nombre: "Alice" }, { id: 2, nombre: "Bob" }] }
  end

  api.post('/usuarios', auth: true, requires: [:nombre, :email]) do |params|
    status 201
    { mensaje: "Usuario creado", usuario: { nombre: params[:nombre], email: params[:email] } }
  end

  api.delete('/usuarios/:id', auth: true) do |params|
    { mensaje: "Usuario #{params[:id]} eliminado" }
  end
end
```

```ruby
# rutas/paises.rb
def registrar_paises(api)
  PAISES = [
    { id: 1, nombre: "México",  capital: "Ciudad de México" },
    { id: 2, nombre: "España",  capital: "Madrid" }
  ]

  api.get('/paises', auth: false) do
    { total: PAISES.size, paises: PAISES }
  end

  api.get('/paises/:id', auth: false) do |params|
    p = PAISES.find { |x| x[:id] == params[:id] }
    status 404 and next { error: "No encontrado" } unless p
    p
  end
end
```

```ruby
# rutas/productos.rb
def registrar_productos(api)
  api.get('/productos', auth: false) do
    { productos: [{ id: 1, nombre: "Laptop", precio: 999.99 }] }
  end

  api.post('/productos', auth: true, requires: [:nombre, :precio]) do |params|
    status 201
    { mensaje: "Producto creado", producto: { nombre: params[:nombre], precio: params[:precio] } }
  end
end
```

```ruby
# main.rb — un servidor, tres grupos de rutas, un solo proceso
require 'gr_api_manager'
require_relative 'rutas/usuarios'
require_relative 'rutas/paises'
require_relative 'rutas/productos'

api = GRApiManager::Server.new(
  port:         4567,
  bearer_token: "secreto",
  prefix:       "/api/v1"
)

registrar_usuarios(api)    # monta: GET/POST /api/v1/usuarios, DELETE /api/v1/usuarios/:id
registrar_paises(api)      # monta: GET /api/v1/paises, GET /api/v1/paises/:id
registrar_productos(api)   # monta: GET/POST /api/v1/productos

api.run!
# Todas las rutas disponibles en un solo proceso en localhost:4567
```

```bash
# Los tres grupos funcionan en el mismo servidor
curl http://localhost:4567/api/v1/usuarios
curl http://localhost:4567/api/v1/paises
curl http://localhost:4567/api/v1/productos

curl -X POST http://localhost:4567/api/v1/usuarios \
  -H "Authorization: Bearer secreto" \
  -H "Content-Type: application/json" \
  -d '{"nombre":"Carlos","email":"carlos@ejemplo.com"}'
```

Este patrón escala limpiamente — agrega nuevos grupos de rutas sin tocar la lógica de `main.rb`, y todos comparten el mismo token, prefijo y límite de body.

---

## Licencia

Disponible como código abierto bajo la [MIT License](https://opensource.org/licenses/MIT).
