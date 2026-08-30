# GR API Manager

[![Gem Version](https://img.shields.io/gem/v/gr_api_manager.svg?logo=rubygems&logoColor=white&color=e9573f)](https://rubygems.org/gems/gr_api_manager)
[![Gem Total Downloads](https://img.shields.io/gem/dt/gr_api_manager.svg?logo=rubygems&logoColor=white&color=00bfa5)](https://rubygems.org/gems/gr_api_manager)
[![Ruby Version](https://img.shields.io/badge/Ruby-%3E%3D%203.0-cc342d.svg?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Sinatra Version](https://img.shields.io/badge/Sinatra-%3E%3D%203.0-008080.svg?logo=sinatra&logoColor=white)](https://sinatrarb.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-007ec6.svg?logo=open-source-initiative&logoColor=white)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-555555.svg?logo=linux&logoColor=white)](https://rubygems.org/gems/gr_api_manager)
[![Tests](https://img.shields.io/badge/Tests-59%2F59%20Passing-4c1.svg?logo=checkmarx&logoColor=white)](spec/)
[![README in English](https://img.shields.io/badge/README-English-blue.svg?logo=google-translate&logoColor=white)](README.md)

**GR API Manager** es un micro-framework y wrapper de alto rendimiento de Ruby sobre Sinatra y Puma, diseñado para construir APIs REST profesionales sin código repetitivo (*zero boilerplate*).

---

## Requisitos del Sistema

| Dependencia / Entorno | Version requerida / soportada |
|---|---|
| **Ruby** | `>= 3.0` (Probado en 3.0, 3.1, 3.2, 3.3 y 3.4) |
| **Sinatra** | `>= 3.0, < 5.0` |
| **Puma** | `>= 5.0, < 9.0` |
| **Dotenv** | `>= 2.8, < 4.0` |

---

## Caracteristicas Principales

- **Disponible en RubyGems (`0.4.0`)** - instalacion global o via Bundler.
- **Grupos de Rutas Modulares (`api.group`)** - organiza proyectos grandes en multiples archivos y modulos independientes con herencia de prefijos y opciones.
- **Autenticacion Dual (Bearer Token Fijo & JWT Nativo)** - soporte para tokens estaticos pre-compartidos y motor JWT (HMAC-SHA256) integrado sin gemas externas.
- **Validacion Declarativa de Esquemas y Tipos** - valida contratos de datos complejos con `:email`, `:url`, `:boolean`, `:file`, clases (`Integer`, `Float`, `String`, `Array`, `Hash`), listas enum, expresiones regulares o lambdas.
- **Control de Tasa (Rate Limiting 429)** - algoritmo *sliding window* con deteccion automatica de IP real tras Cloudflare (`CF-Connecting-IP`), Nginx (`X-Real-IP`) o Proxies (`X-Forwarded-For`), con soporte para almacenes en memoria o externos (Redis).
- **Cast Inteligente de Tipos** - conversion automatica de parametros de query/URL (`"100"` -> `100`, `"-42"` -> `-42`, `"true"` -> `true`, `"19.99"` -> `19.99`).
- **Manejo Integral de Archivos y Binarios (`FilePayload`)** - soporte transparente para uploads multipart, flujos binarios crudos, conversion a Base64, Hexadecimal, descarga de archivos y guardado automatico en disco.
- **Servidor Concurrente Puma** - soporte para multiples procesos worker y pools de threads.
- **Modo de Depuracion (`dev_mode`)** - errores 500 estructurados en JSON con stack trace detallado para desarrollo.

---

## Instalacion

Agrega la gema a tu `Gemfile`:
```ruby
gem 'gr_api_manager', '~> 0.4.0'
```

Y ejecuta:
```bash
bundle install
```

O instalala directamente en tu sistema:
```bash
gem install gr_api_manager
```

---

## Tabla de Contenidos

1. [Inicio Rapido](#inicio-rapido)
2. [Autenticacion: Token Fijo (Bearer) y JWT Nativo](#autenticacion-token-fijo-bearer-y-jwt-nativo)
3. [Estructura Modular Multi-Archivo (Importar y Agrupar)](#estructura-modular-multi-archivo)
4. [CRUD Completo con Verbos HTTP](#crud-completo-con-verbos-http)
5. [Validacion Declarativa de Esquemas y Tipos](#validacion-declarativa-de-esquemas-y-tipos)
6. [Manejo Integral de Archivos, Binarios e Imagenes](#manejo-integral-de-archivos-binarios-e-imagenes)
7. [Descarga y Servir Archivos al Cliente](#descarga-y-servir-archivos-al-cliente)
8. [Rate Limiting y Deteccion de IP Real (Cloudflare/Nginx)](#rate-limiting-y-deteccion-de-ip-real)
9. [Cast Inteligente de Parametros](#cast-inteligente-de-parametros)
10. [Respuestas, Codigos HTTP y Modo Desarrollo](#respuestas-codigos-http-y-modo-desarrollo)
11. [Concurrencia y Produccion (Puma & Docker)](#concurrencia-y-produccion)

---

## Inicio Rapido

Crea un archivo `app.rb`:

```ruby
require 'gr_api_manager'

# Inicializa el servidor con un token fijo y clave JWT
api = GRApiManager::Server.new(
  port: 4000,
  bearer_token: "mi_token_fijo_secreto",
  jwt_secret: "mi_firma_jwt"
)

# Endpoint publico (sin autenticacion)
api.get('/health', auth: false) do
  { status: 'online', timestamp: Time.now.to_i }
end

# Endpoint protegido con token fijo (default: auth = true)
api.get('/datos-protegidos') do
  { mensaje: "Acceso autorizado con Bearer Token", datos: [10, 20, 30] }
end

# Inicia el servidor
api.run!
```

Ejecuta tu API:
```bash
ruby app.rb
```

---

## Autenticacion: Token Fijo (Bearer) y JWT Nativo

`gr_api_manager` soporta dos esquemas de autenticacion complementarios:

### 1. Token Fijo (Static Bearer Token)

Ideal para APIs privadas, comunicacion entre microservicios, webhooks o scripts backend donde existe una clave fija pre-compartida.

#### Configuracion en `app.rb`:
```ruby
api = GRApiManager::Server.new(
  bearer_token: "clave_secreta_empresa_2026"
)

# Ruta publica
api.get('/publico', auth: false) do
  { estado: "acceso libre" }
end

# Rutas protegidas (por defecto auth: true)
api.get('/admin/config') do
  { base_datos: "conectada", entorno: "produccion" }
end

api.post('/admin/reiniciar', requires: [:motivo]) do |params|
  { accion: "reiniciando", motivo: params[:motivo] }
end
```

#### Como consumir desde cURL o clientes HTTP:

**Peticion valida (200 OK):**
```bash
curl -H "Authorization: Bearer clave_secreta_empresa_2026" http://localhost:4000/admin/config
# => {"base_datos":"conectada","entorno":"produccion"}
```

**Peticion sin cabecera (401 Unauthorized):**
```bash
curl http://localhost:4000/admin/config
# => 401 {"error":"Token required. Format: 'Bearer <token>'"}
```

**Peticion con token invalido (403 Forbidden):**
```bash
curl -H "Authorization: Bearer token_falso" http://localhost:4000/admin/config
# => 403 {"error":"Invalid token"}
```

---

### 2. Autenticacion JWT Nativa (HS256)

Ideal para APIs con usuarios finales donde se emiten tokens dinamicos con roles y tiempo de expiracion.

#### Configuracion y Flujo Completo:
```ruby
api = GRApiManager::Server.new(
  jwt_secret: "clave_secreta_para_firmar_jwts"
)

# 1. Login: genera y entrega el token al usuario
api.post('/auth/login', auth: false, requires: { email: :email, password: String }) do |params|
  # Validar credenciales contra base de datos
  if params[:email] == "admin@empresa.com" && params[:password] == "pass123"
    token = api.jwt_encode(
      { user_id: 42, email: params[:email], role: "admin" },
      exp: Time.now.to_i + 3600 # Expira en 1 hora
    )
    { token: token, token_type: "Bearer", expira_en: 3600 }
  else
    status 401
    { error: "Credenciales invalidas" }
  end
end

# 2. Ruta protegida por JWT: inyecta automaticamente params[:current_user]
api.get('/perfil', auth: :jwt) do |params|
  usuario = params[:current_user]
  {
    mensaje: "Token JWT valido",
    id_usuario: usuario[:user_id],
    email: usuario[:email],
    rol: usuario[:role]
  }
end
```

---

## Estructura Modular Multi-Archivo

Divide tu API en modulos independientes y ordenados dentro de una carpeta `routes/`:

```text
mi_proyecto/
├── app.rb                   # Archivo principal de configuracion y arranque
├── .env                     # Variables de entorno
├── Gemfile
└── routes/
    ├── auth_routes.rb       # Login y registro
    ├── admin_routes.rb      # Panel de administracion
    ├── pagos_routes.rb      # Pasarela de pagos
    └── archivos_routes.rb   # Subida y descarga de archivos
```

### Modulo 1: `routes/auth_routes.rb`
```ruby
module AuthRoutes
  def self.setup(router, api_server)
    router.post('/login', auth: false, requires: { email: :email, password: String }) do |params|
      if params[:email] == "admin@empresa.com" && params[:password] == "secreto"
        token = api_server.jwt_encode({ user_id: 1, email: params[:email], role: "admin" })
        { token: token }
      else
        status 401
        { error: "Credenciales incorrectas" }
      end
    end
  end
end
```

### Modulo 2: `routes/admin_routes.rb`
```ruby
module AdminRoutes
  def self.setup(router)
    router.get('/metricas') do |params|
      { cpu: "12%", memoria: "380MB", usuario: params[:current_user][:email] }
    end

    router.delete('/usuarios/:id') do |params|
      { mensaje: "Usuario #{params[:id]} eliminado" }
    end
  end
end
```

### Modulo 3: `routes/archivos_routes.rb`
```ruby
module ArchivosRoutes
  def self.setup(router)
    router.post('/subir', requires: [:nombre]) do |params|
      archivo = params[:_files][:documento]
      ruta = archivo.save_to("./almacen/#{params[:nombre]}#{archivo.extension}")
      { status: "guardado", ruta: ruta, tamano: archivo.size }
    end
  end
end
```

### Archivo Principal: `app.rb`
```ruby
require 'gr_api_manager'

# Importar los modulos de rutas
require_relative 'routes/auth_routes'
require_relative 'routes/admin_routes'
require_relative 'routes/archivos_routes'

api = GRApiManager::Server.new(
  port: 4000,
  jwt_secret: ENV['JWT_SECRET'] || "clave_jwt_por_defecto",
  bearer_token: ENV['API_TOKEN'] || "token_fijo_global"
)

# Ruta raiz
api.get('/', auth: false) { { servicio: "API Central v1.0" } }

# Montar los grupos de rutas
api.group('/auth') { |g| AuthRoutes.setup(g, api) }
api.group('/admin', auth: :jwt) { |g| AdminRoutes.setup(g) }
api.group('/archivos', auth: true) { |g| ArchivosRoutes.setup(g) }

api.run!(workers: 2, threads: '2:8')
```

---

## CRUD Completo con Verbos HTTP

Ejemplo de gestion completa de un recurso `/productos`:

```ruby
api = GRApiManager::Server.new(prefix: '/api/v1')

# 1. LISTAR (GET) - con parametros query auto-casteados
api.get('/productos', auth: false) do |params|
  pagina = params[:pagina] || 1       # Integer
  limite = params[:limite] || 10      # Integer
  activo = params[:activo] != false   # Boolean
  
  {
    pagina: pagina,
    limite: limite,
    items: [
      { id: 1, nombre: "Teclado Mecanico", precio: 89.99, activo: true },
      { id: 2, nombre: "Monitor 4K", precio: 299.99, activo: true }
    ]
  }
end

# 2. OBTENER POR ID (GET)
api.get('/productos/:id', auth: false) do |params|
  id = params[:id] # Integer automatico
  { id: id, nombre: "Producto #{id}", precio: 49.99 }
end

# 3. CREAR (POST) - con validacion de tipos
api.post('/productos', requires: { nombre: String, precio: Float, categoria: ['tech', 'oficina'] }) do |params|
  status 201
  {
    mensaje: "Producto creado",
    producto: { id: rand(100..999), nombre: params[:nombre], precio: params[:precio] }
  }
end

# 4. REEMPLAZAR COMPLETO (PUT)
api.put('/productos/:id', requires: { nombre: String, precio: Float }) do |params|
  {
    mensaje: "Producto #{params[:id]} actualizado por completo",
    datos: params
  }
end

# 5. ACTUALIZACION PARCIAL (PATCH)
api.patch('/productos/:id') do |params|
  {
    mensaje: "Campos modificados en producto #{params[:id]}",
    cambios: params.except(:id)
  }
end

# 6. ELIMINAR (DELETE)
api.delete('/productos/:id') do |params|
  { mensaje: "Producto #{params[:id]} eliminado con exito" }
end
```

---

## Validacion Declarativa de Esquemas y Tipos

La opcion `requires:` permite validar tipos de datos, formatos de texto, archivos y reglas personalizadas:

```ruby
api.post '/catalogo', requires: {
  codigo:     /^[A-Z]{3}-\d{4}$/,           # Regex: ej. "PRO-1234"
  titulo:     String,                       # Cadena no vacia
  precio:     Float,                        # Numero decimal
  stock:      Integer,                      # Numero entero
  activo:     :boolean,                     # true o false
  categoria:  ['electronica', 'hogar'],     # Enum / Lista de opciones
  foto:       :file,                        # Archivo subido (FilePayload)
  web_fab:    :url,                         # URL valida (http/https)
  contacto:   :email,                       # Correo electronico valido
  descuento:  ->(v) { v.to_f.between?(0, 100) } # Lambda personalizada
} do |params|
  status 201
  { status: "ok", item: params[:titulo] }
end
```

### Tabla de Reglas de Validacion:

| Regla | Tipo / Formato | Ejemplo valido |
|---|---|---|
| `:email` | Correo electronico estandar | `"contacto@dominio.com"` |
| `:url` | URL con protocolo `http://` o `https://` | `"https://api.empresa.com"` |
| `:boolean` | Booleano nativo (`true` o `false`) | `true`, `false` |
| `:file` | Instancia de `GRApiManager::FilePayload` | Archivo subido via multipart |
| `Integer` | Numero entero | `42`, `100`, `-10` |
| `Float` | Numero de coma flotante | `19.99`, `0.5`, `-3.14` |
| `Numeric` | Cualquier numero (`Integer` o `Float`) | `10`, `3.14` |
| `String` | Cadena de texto no vacia | `"Texto"` |
| `Array` | Arreglo de elementos | `[1, 2, 3]` |
| `Hash` | Objeto o diccionario JSON | `{ clave: "valor" }` |
| `['a', 'b']` | Inclusion obligatoria en lista (Enum) | `'electronica'` |
| `/^regex$/` | Expresion regular | `"ABC-1234"` |
| `->(val) { ... }` | Funcion / Lambda (debe retornar `true`) | `->(n) { n.to_i > 0 }` |

---

## Manejo Integral de Archivos, Binarios e Imagenes

`gr_api_manager` detecta automaticamente el `Content-Type` de la peticion y unifica el acceso mediante la clase `FilePayload`:

### 1. Subida Multipart (`multipart/form-data`)
```ruby
api.post('/perfil/avatar', requires: [:usuario_id]) do |params|
  avatar = params[:_files][:avatar] # FilePayload

  # Guardar en disco (crea carpetas intermedias automaticamente)
  ruta = avatar.save_to("./almacen/avatares/user_#{params[:usuario_id]}#{avatar.extension}")

  {
    mensaje: "Avatar guardado",
    archivo: avatar.filename,
    tamano: avatar.size,
    extension: avatar.extension,
    guardado_en: ruta
  }
end
```

#### cURL multipart:
```bash
curl -X POST http://localhost:4000/perfil/avatar \
  -H "Authorization: Bearer mi_token" \
  -F "usuario_id=10" \
  -F "avatar=@/ruta/a/mi_foto.jpg"
```

---

### 2. Subida de Binario Crudo (Raw Binary / Image / PDF Stream)

Envio directo de bytes en el body de la peticion (sin multipart):

```ruby
api.post('/documentos/raw') do |params|
  archivo = params[:_raw_binary] # FilePayload

  archivo.save_to("./almacen/docs/#{archivo.filename}")
  
  {
    formato: "binario crudo",
    nombre_detectado: archivo.filename,
    tamano_bytes: archivo.size,
    mime_type: archivo.content_type,
    hex_inicial: archivo.to_hex[0..30]
  }
end
```

#### cURL binario crudo:
```bash
curl -X POST http://localhost:4000/documentos/raw \
  -H "Authorization: Bearer mi_token" \
  -H "Content-Type: application/pdf" \
  -H "Content-Disposition: attachment; filename=\"contrato.pdf\"" \
  --data-binary @contrato.pdf
```

---

### 3. Conversion a Base64 y Hexadecimal
```ruby
api.post('/archivos/convertir') do |params|
  archivo = params[:_files][:archivo]

  {
    base64: archivo.to_base64, # Cadena Base64 limpia (sin saltos de linea)
    hexadecimal: archivo.to_hex, # Cadena Hexadecimal en minusculas
    bytes_totales: archivo.size
  }
end
```

---

### 4. Subida en Texto Plano (`text/plain`)
```ruby
api.post('/logs/texto') do |params|
  texto_crudo = params[:_raw_text] # String UTF-8
  { lineas: texto_crudo.lines.count, caracteres: texto_crudo.length }
end
```

---

## Descarga y Servir Archivos al Cliente

Si retornas un `String` desde el bloque de la ruta, `gr_api_manager` lo entrega **directamente como flujo de datos**, permitiendo servir imagenes, PDFs o descargas binarias:

```ruby
api.get('/descargas/foto/:id', auth: false) do |params|
  ruta_foto = "./almacen/avatares/user_#{params[:id]}.jpg"
  
  unless File.exist?(ruta_foto)
    status 404
    next { error: "Foto no encontrada" }
  end

  # Configurar cabeceras de respuesta HTTP
  content_type 'image/jpeg'
  headers 'Content-Disposition' => "inline; filename=\"foto_#{params[:id]}.jpg\""
  
  # Retornar los bytes del archivo directamente
  File.binread(ruta_foto)
end
```

---

## Rate Limiting y Deteccion de IP Real

Protege tu API con control de tasa deslizante (*sliding-window*) por IP de cliente:

```ruby
api = GRApiManager::Server.new(
  rate_limit:          60,   # Maximo 60 peticiones
  rate_limit_window:   60,   # por cada ventana de 60 segundos
  trust_proxy_headers: true  # Lee CF-Connecting-IP, X-Real-IP, X-Forwarded-For
)
```

Cabeceras HTTP devueltas en cada peticion:
* `X-RateLimit-Limit`: Limite maximo permitido (`60`).
* `X-RateLimit-Remaining`: Peticiones restantes en la ventana actual.
* `X-RateLimit-Reset`: Timestamp Unix cuando se reinicia la cuota.
* `Retry-After`: Segundos a esperar si se excede el limite (`429 Too Many Requests`).

---

## Cast Inteligente de Parametros

Los parametros de URL y Query String se transforman automaticamente a tipos nativos de Ruby:

```ruby
api.get('/analisis') do |params|
  # Peticion: /analisis?id=123&activo=true&descuento=15.5&saldo=-500&categoria=tech
  
  params[:id]        # => 123 (Integer)
  params[:activo]    # => true (TrueClass)
  params[:descuento] # => 15.5 (Float)
  params[:saldo]     # => -500 (Integer)
  params[:categoria] # => "tech" (String)
  
  { status: "ok" }
end
```

---

## Respuestas, Codigos HTTP y Modo Desarrollo

### Codigos de estado personalizados:
```ruby
api.post('/recursos') do
  status 201 # Created
  { mensaje: "Recurso creado" }
end
```

### Modo Desarrollo (`dev_mode: true`):
En desarrollo, activa `dev_mode: true` para obtener detalles exactos y stack traces en JSON al ocurrir un error inesperado (500):

```ruby
api = GRApiManager::Server.new(dev_mode: true)
```

Respuesta en 500:
```json
{
  "error": "Internal Server Error",
  "details": "undefined local variable or method 'variable_inexistente'",
  "class": "NameError",
  "backtrace": [
    "/app/routes/usuarios.rb:14:in `block in setup'",
    "/lib/gr_api_manager.rb:482:in `instance_exec'"
  ]
}
```

---

## Concurrencia y Produccion

### Ejecutar con Puma en Produccion:
```ruby
# Inicia con 4 procesos worker y entre 4 y 16 threads por worker
api.run!(workers: 4, threads: '4:16')
```

### Dockerfile de Produccion:
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

## Pruebas Automatizadas

El framework incluye una suite completa con **RSpec** y **Rack::Test**:

```bash
rspec
# => 59 examples, 0 failures
```

---

## Licencia

Este proyecto esta bajo la licencia [MIT](LICENSE). Creado por **Gabo Razo**.
