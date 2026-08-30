require 'sinatra/base'
require 'json'
require 'dotenv/load'
require 'base64'
require 'tempfile'
require 'fileutils'
require 'openssl'

module GRApiManager
  # Convenience size helpers — use in max_body_size:
  #   GRApiManager.mb(50)   => 50 MB in bytes
  #   GRApiManager.gb(2)    => 2 GB in bytes
  def self.mb(n) = n * 1_024 * 1_024
  def self.gb(n) = n * 1_024 * 1_024 * 1_024

  # Extracts the client IP from proxy headers (Cloudflare, X-Real-IP, X-Forwarded-For),
  # falling back to request.ip or REMOTE_ADDR.
  def self.extract_client_ip(request)
    env = request.respond_to?(:env) ? request.env : request
    return (request.respond_to?(:ip) ? request.ip : '127.0.0.1') unless env.is_a?(Hash)

    if env['HTTP_CF_CONNECTING_IP'] && !env['HTTP_CF_CONNECTING_IP'].to_s.strip.empty?
      return env['HTTP_CF_CONNECTING_IP'].to_s.strip
    end

    if env['HTTP_X_REAL_IP'] && !env['HTTP_X_REAL_IP'].to_s.strip.empty?
      return env['HTTP_X_REAL_IP'].to_s.strip
    end

    if env['HTTP_X_FORWARDED_FOR'] && !env['HTTP_X_FORWARDED_FOR'].to_s.strip.empty?
      client = env['HTTP_X_FORWARDED_FOR'].to_s.split(',').first
      return client.strip if client && !client.strip.empty?
    end

    request.respond_to?(:ip) ? request.ip : (env['REMOTE_ADDR'] || '127.0.0.1')
  end

  # ---------------------------------------------------------------------------
  # JWT — Zero-dependency JSON Web Token encoder and decoder (HS256).
  # ---------------------------------------------------------------------------
  module JWT
    class DecodeError < StandardError; end
    class ExpiredSignature < DecodeError; end

    def self.base64url_encode(str)
      Base64.urlsafe_encode64(str, padding: false)
    end

    def self.base64url_decode(str)
      padded = str + ('=' * ((4 - (str.length % 4)) % 4))
      Base64.urlsafe_decode64(padded)
    rescue ArgumentError => e
      raise DecodeError, "Invalid Base64URL string: #{e.message}"
    end

    # Encodes a payload hash into a JWT token signed with HMAC-SHA256.
    # Options:
    #   exp: Integer – expiration timestamp (epoch in seconds).
    def self.encode(payload, secret, exp: nil, algorithm: 'HS256')
      raise ArgumentError, "JWT secret cannot be blank" if secret.to_s.strip.empty?

      data = payload.dup
      data = data.transform_keys(&:to_sym) if data.is_a?(Hash)
      data[:exp] = exp.to_i if exp

      header = { typ: 'JWT', alg: algorithm }
      header_b64    = base64url_encode(header.to_json)
      payload_b64   = base64url_encode(data.to_json)
      signing_input = "#{header_b64}.#{payload_b64}"

      digest        = OpenSSL::Digest.new('sha256')
      signature     = OpenSSL::HMAC.digest(digest, secret.to_s, signing_input)
      signature_b64 = base64url_encode(signature)

      "#{signing_input}.#{signature_b64}"
    end

    # Decodes and verifies a JWT token. Returns the payload hash with symbolized keys.
    def self.decode(token, secret)
      raise ArgumentError, "JWT secret cannot be blank" if secret.to_s.strip.empty?
      raise DecodeError, "Token cannot be blank" if token.nil? || token.to_s.strip.empty?

      parts = token.to_s.split('.')
      raise DecodeError, "Invalid JWT format. Expected 3 segments separated by dots." unless parts.size == 3

      header_b64, payload_b64, signature_b64 = parts
      signing_input = "#{header_b64}.#{payload_b64}"

      digest       = OpenSSL::Digest.new('sha256')
      expected_sig = OpenSSL::HMAC.digest(digest, secret.to_s, signing_input)
      actual_sig   = base64url_decode(signature_b64)

      is_valid = if OpenSSL.respond_to?(:secure_compare)
                   OpenSSL.secure_compare(expected_sig, actual_sig)
                 else
                   expected_sig == actual_sig
                 end

      raise DecodeError, "Invalid JWT signature" unless is_valid

      payload_json = base64url_decode(payload_b64)
      payload      = JSON.parse(payload_json, symbolize_names: true)

      if payload[:exp]
        exp_time = payload[:exp].to_i
        raise ExpiredSignature, "JWT signature has expired" if Time.now.to_i > exp_time
      end

      payload
    rescue JSON::ParserError => e
      raise DecodeError, "Invalid JSON payload in token: #{e.message}"
    end
  end

  # ---------------------------------------------------------------------------
  # Validator — declarative schema and type validation.
  # ---------------------------------------------------------------------------
  module Validator
    EMAIL_REGEX = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
    URL_REGEX   = /\Ahttps?:\/\/\S+\z/i

    # Validates *params* against *schema* (Hash of field => expected_type).
    # Returns [is_valid, errors_hash].
    def self.validate(params, schema)
      errors = {}

      schema.each do |field, rule|
        key = field.to_sym
        val = params[key]

        # Check presence
        if val.nil? || (val.is_a?(String) && val.strip.empty?)
          errors[key] = "is required"
          next
        end

        # Validate type / contract rule
        error_msg = validate_rule(val, rule)
        errors[key] = error_msg if error_msg
      end

      [errors.empty?, errors]
    end

    private_class_method

    def self.validate_rule(val, rule)
      case rule
      when :email
        "must be a valid email address" unless val.to_s.match?(EMAIL_REGEX)
      when :url
        "must be a valid URL (http/https)" unless val.to_s.match?(URL_REGEX)
      when :boolean
        "must be a boolean (true or false)" unless val == true || val == false
      when :file
        "must be an uploaded file" unless val.is_a?(GRApiManager::FilePayload)
      when Class
        if rule == Integer
          "must be an Integer" unless val.is_a?(Integer)
        elsif rule == Float
          "must be a Float" unless val.is_a?(Float)
        elsif rule == Numeric
          "must be a Numeric" unless val.is_a?(Numeric)
        elsif rule == String
          "must be a String" unless val.is_a?(String)
        elsif rule == Hash
          "must be an Object/Hash" unless val.is_a?(Hash)
        elsif rule == Array
          "must be an Array" unless val.is_a?(Array)
        else
          "must be a #{rule}" unless val.is_a?(rule)
        end
      when Array
        "must be one of: #{rule.map(&:to_s).join(', ')}" unless rule.map(&:to_s).include?(val.to_s)
      when Regexp
        "does not match expected format" unless val.to_s.match?(rule)
      when Proc
        "is invalid" unless rule.call(val)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # RateLimiter — thread-safe sliding-window rate limiter per IP/key.
  #
  # Supports pluggable storage backends (default: MemoryStore with Mutex).
  # Prevents client flooding and supports distributed stores like Redis.
  # ---------------------------------------------------------------------------
  class RateLimiter
    attr_reader :max_requests, :window_seconds, :store

    # In-memory sliding-window store using Mutex.
    class MemoryStore
      def initialize
        @store = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      def allow?(key, max, window)
        @mutex.synchronize do
          now    = Time.now.to_f
          cutoff = now - window
          @store[key].reject! { |t| t < cutoff }
          return false if @store[key].size >= max
          @store[key] << now
          true
        end
      end

      def remaining(key, max, window)
        @mutex.synchronize do
          cutoff = Time.now.to_f - window
          active = @store[key].count { |t| t >= cutoff }
          [max - active, 0].max
        end
      end

      def cleanup!(window)
        @mutex.synchronize do
          cutoff = Time.now.to_f - window
          @store.each_value { |times| times.reject! { |t| t < cutoff } }
          @store.delete_if  { |_, times| times.empty? }
        end
      end

      def reset!(key = nil)
        @mutex.synchronize do
          if key
            @store.delete(key)
          else
            @store.clear
          end
        end
      end

      def size
        @mutex.synchronize { @store.size }
      end
    end

    def initialize(max_requests:, window_seconds:, store: nil)
      @max_requests   = max_requests
      @window_seconds = window_seconds
      @store          = store || MemoryStore.new
    end

    # Returns true if the request from *key* is within the allowed rate.
    def allow?(key)
      if @store.respond_to?(:allow?)
        if @store.method(:allow?).arity == 1
          @store.allow?(key)
        else
          @store.allow?(key, @max_requests, @window_seconds)
        end
      else
        true
      end
    end

    # Remaining requests allowed for *key* in the current window.
    def remaining(key)
      if @store.respond_to?(:remaining)
        if @store.method(:remaining).arity == 1
          @store.remaining(key)
        else
          @store.remaining(key, @max_requests, @window_seconds)
        end
      else
        @max_requests
      end
    end

    # Removes stale entries — call periodically to prevent memory growth.
    def cleanup!
      if @store.respond_to?(:cleanup!)
        if @store.method(:cleanup!).arity == 0
          @store.cleanup!
        else
          @store.cleanup!(@window_seconds)
        end
      end
    end

    # Resets counters for a specific key or all keys.
    def reset!(key = nil)
      @store.reset!(key) if @store.respond_to?(:reset!)
    end

    # Summary hash — safe to log or expose on a diagnostic endpoint.
    def stats
      tracked = @store.respond_to?(:size) ? @store.size : :external
      { tracked_ips: tracked, max_requests: @max_requests, window_seconds: @window_seconds }
    end
  end

  # ---------------------------------------------------------------------------
  # FilePayload — wraps an uploaded file (multipart or raw) with a clean API.
  # ---------------------------------------------------------------------------
  class FilePayload
    attr_reader :filename, :content_type, :size, :tempfile

    def initialize(tempfile:, filename:, content_type:)
      @tempfile     = tempfile
      @filename     = filename.to_s
      @content_type = content_type.to_s
      @size         = tempfile.respond_to?(:size) ? tempfile.size : (tempfile.respond_to?(:length) ? tempfile.length : tempfile.to_s.bytesize)
    end

    # Returns the raw binary content of the file as a String (encoding: BINARY).
    def read
      if @tempfile.respond_to?(:read)
        @tempfile.rewind if @tempfile.respond_to?(:rewind)
        @tempfile.read
      else
        @tempfile.to_s.dup.force_encoding(Encoding::BINARY)
      end
    end

    # Returns the file content encoded as a Base64 string (no newlines).
    def to_base64
      Base64.strict_encode64(read)
    end

    # Returns the file content encoded as a lowercase hexadecimal string.
    def to_hex
      read.unpack1('H*')
    end

    # Saves the uploaded content to *dest_path* on disk. Returns dest_path.
    def save_to(dest_path)
      dir = File.dirname(dest_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      File.open(dest_path, 'wb') { |f| f.write(read) }
      dest_path
    end

    # Convenience: the file extension derived from the original filename.
    def extension
      File.extname(@filename).downcase
    end

    # Human-friendly summary — safe to include in JSON responses.
    def to_h
      {
        filename:     @filename,
        content_type: @content_type,
        size:         @size,
        extension:    extension
      }
    end

    def inspect
      "#<GRApiManager::FilePayload filename=#{@filename.inspect} " \
        "content_type=#{@content_type.inspect} size=#{@size}>"
    end
  end

  # ---------------------------------------------------------------------------
  # BodyParser — detects Content-Type and returns an appropriate parsed result.
  # ---------------------------------------------------------------------------
  module BodyParser

    BINARY_MIME_PREFIXES = %w[
      image/ video/ audio/ application/pdf application/msword
      application/vnd. application/zip application/x-tar
      application/x-rar application/octet-stream
    ].freeze

    # Returns a Hash of parsed body values.
    def self.parse(request)
      content_type = (request.content_type || '').split(';').first.to_s.strip.downcase

      case content_type
      when 'application/json'
        parse_json(request)

      when 'multipart/form-data'
        parse_multipart(request)

      when 'application/x-www-form-urlencoded'
        {}

      when 'text/plain'
        text = request.body.read.to_s.force_encoding(Encoding::UTF_8)
        { _raw_text: text }

      else
        if binary_content_type?(content_type)
          parse_raw_binary(request, content_type)
        else
          parse_json(request) rescue {}
        end
      end
    end

    private_class_method

    def self.parse_json(request)
      body = request.body.read.to_s
      return {} if body.strip.empty?
      JSON.parse(body, symbolize_names: true)
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON body: #{e.message}"
    end

    def self.parse_multipart(request)
      result = {}
      files  = {}

      request.params.each do |key, value|
        sym = key.to_sym

        if value.is_a?(Hash) && value.key?(:tempfile)
          files[sym] = FilePayload.new(
            tempfile:     value[:tempfile],
            filename:     value[:filename] || key,
            content_type: value[:type] || 'application/octet-stream'
          )
        elsif value.is_a?(Array)
          files[sym] = value.map do |v|
            if v.is_a?(Hash) && v.key?(:tempfile)
              FilePayload.new(
                tempfile:     v[:tempfile],
                filename:     v[:filename] || key,
                content_type: v[:type] || 'application/octet-stream'
              )
            else
              v
            end
          end
        else
          result[sym] = value
        end
      end

      result[:_files] = files unless files.empty?
      result
    end

    def self.parse_raw_binary(request, content_type)
      raw = request.body.read
      return {} if raw.nil? || raw.empty?

      disposition = request.env['HTTP_CONTENT_DISPOSITION'] || ''
      filename    = disposition[/filename="?([^";]+)"?/, 1] || "upload#{ext_for(content_type)}"

      io = StringIO.new(raw.force_encoding(Encoding::BINARY))

      payload = FilePayload.new(
        tempfile:     io,
        filename:     filename,
        content_type: content_type
      )

      { _raw_binary: payload }
    end

    def self.binary_content_type?(ct)
      BINARY_MIME_PREFIXES.any? { |prefix| ct.start_with?(prefix) }
    end

    def self.ext_for(content_type)
      {
        'image/jpeg'          => '.jpg',
        'image/png'           => '.png',
        'image/gif'           => '.gif',
        'image/webp'          => '.webp',
        'image/svg+xml'       => '.svg',
        'image/bmp'           => '.bmp',
        'video/mp4'           => '.mp4',
        'video/webm'          => '.webm',
        'audio/mpeg'          => '.mp3',
        'audio/wav'           => '.wav',
        'application/pdf'     => '.pdf',
        'application/msword'  => '.doc',
        'application/zip'     => '.zip',
        'application/x-tar'   => '.tar',
        'application/octet-stream' => '.bin'
      }.fetch(content_type, '.bin')
    end
  end

  # ---------------------------------------------------------------------------
  # RouteGroup — provides nested route grouping with shared prefixes and options.
  # ---------------------------------------------------------------------------
  class RouteGroup
    attr_reader :server, :prefix, :options

    def initialize(server, prefix = '', options = {})
      @server  = server
      @prefix  = prefix.to_s
      @options = options
    end

    # Dynamically generate routing methods inside the group (get, post, put, patch, delete).
    %w[get post put patch delete].each do |verb|
      define_method(verb) do |path, route_options = {}, &block|
        combined_path   = File.join('/', @prefix, path.to_s).gsub(%r{/+}, '/')
        merged_options  = @options.merge(route_options)

        if @options[:requires] && route_options[:requires]
          merged_options[:requires] = merge_requires(@options[:requires], route_options[:requires])
        end

        @server.register_route(verb, combined_path, merged_options, &block)
      end
    end

    # Nested sub-grouping.
    def group(sub_prefix = '', sub_options = {}, &block)
      combined_prefix = File.join('/', @prefix, sub_prefix.to_s).gsub(%r{/+}, '/')
      merged_options  = @options.merge(sub_options)

      if @options[:requires] && sub_options[:requires]
        merged_options[:requires] = merge_requires(@options[:requires], sub_options[:requires])
      end

      sub_group = RouteGroup.new(@server, combined_prefix, merged_options)
      block.call(sub_group) if block
      sub_group
    end

    private

    def merge_requires(req1, req2)
      if req1.is_a?(Hash) && req2.is_a?(Hash)
        req1.merge(req2)
      elsif req1.is_a?(Array) && req2.is_a?(Array)
        (req1 + req2).uniq
      else
        req2
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Server — the public-facing DSL.
  # ---------------------------------------------------------------------------
  class Server
    attr_reader :app_class, :rate_limiter, :jwt_secret

    # Initializes the server configuration.
    #
    # Options:
    #   port:                 Integer  – listening port (default: ENV['PORT'] || 4000)
    #   bearer_token:         String   – Bearer token for auth (default: ENV['API_TOKEN'])
    #   jwt_secret:           String   – Secret key for signing/decoding JWTs (default: ENV['JWT_SECRET'])
    #   permitted_hosts:      Array    – host allowlist; empty = allow all
    #   prefix:               String   – route prefix, e.g. '/api/v1'
    #   max_body_size:        Integer  – maximum accepted body in bytes (default: 50 MB)
    #   dev_mode:             Boolean  – show full stack traces on 500 (default: false)
    #   rate_limit:           Integer  – max requests per IP per window (nil = disabled)
    #   rate_limit_window:    Integer  – sliding window in seconds (default: 60)
    #   rate_limit_store:     Object   – custom store object (default: MemoryStore)
    #   trust_proxy_headers:  Boolean  – inspect Cloudflare/X-Real-IP/X-Forwarded-For headers (default: true)
    def initialize(
      port: nil,
      bearer_token: nil,
      jwt_secret: nil,
      permitted_hosts: [],
      prefix: '',
      max_body_size:        GRApiManager.mb(50),
      dev_mode:             false,
      rate_limit:           nil,
      rate_limit_window:    60,
      rate_limit_store:     nil,
      trust_proxy_headers:  true
    )
      @port                = port || ENV['PORT'] || 4000
      @token               = bearer_token || ENV['API_TOKEN']
      @jwt_secret          = jwt_secret || ENV['JWT_SECRET']
      @permitted_hosts     = permitted_hosts.empty? ? [] : permitted_hosts
      @prefix              = prefix
      @max_body_size       = max_body_size
      @dev_mode            = dev_mode
      @trust_proxy_headers = trust_proxy_headers
      @rate_limiter        = rate_limit ? GRApiManager::RateLimiter.new(
                               max_requests:   rate_limit,
                               window_seconds: rate_limit_window,
                               store:          rate_limit_store
                             ) : nil

      @app_class = Class.new(Sinatra::Base) do

        # Logs HTTP requests with status-based color coding.
        def log_request(method, path, status_code)
          color = status_code.between?(200, 299) ? "\e[32m" : "\e[31m"
          puts "[#{Time.now.strftime('%H:%M:%S')}] #{color}#{method} #{path} - #{status_code}\e[0m"
        end

        # Casts string URL parameters to native Ruby types (Integer, Float, Boolean).
        def smart_parse(hash)
          hash.transform_values do |val|
            next val unless val.is_a?(String)
            case val
            when 'true'            then true
            when 'false'           then false
            when /^-?\d+$/         then val.to_i
            when /^-?\d+\.\d+$/    then val.to_f
            else val
            end
          end
        end
      end

      configure_app
    end

    # Encodes a payload into a JWT token using the configured jwt_secret.
    def jwt_encode(payload, exp: nil)
      raise "No jwt_secret configured for this server" unless @jwt_secret
      GRApiManager::JWT.encode(payload, @jwt_secret, exp: exp)
    end

    # Decodes a JWT token using the configured jwt_secret.
    def jwt_decode(token)
      raise "No jwt_secret configured for this server" unless @jwt_secret
      GRApiManager::JWT.decode(token, @jwt_secret)
    end

    # Groups routes under a common prefix with inherited options.
    def group(prefix = '', options = {}, &block)
      route_group = RouteGroup.new(self, prefix, options)
      block.call(route_group) if block
      route_group
    end

    private

    # Sets up Sinatra environment, CORS policies, body size limit, rate limiting, and global error handlers.
    def configure_app
      app                 = @app_class
      max_body            = @max_body_size
      rate_limiter        = @rate_limiter
      trust_proxy_headers = @trust_proxy_headers

      app.set :port,               @port
      app.set :bind,               '0.0.0.0'
      app.set :token,              @token
      app.set :jwt_secret,         @jwt_secret
      app.set :dev_mode,           @dev_mode
      app.set :show_exceptions,    false
      app.set :raise_errors,       false
      app.set :dump_errors,        false
      app.set :host_authorization, { permitted_hosts: @permitted_hosts }
      app.enable :static

      app.before do
        headers 'Access-Control-Allow-Origin'  => '*',
                'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization, Content-Disposition'

        # Rate limiting — checked before anything else.
        if rate_limiter
          client_ip = trust_proxy_headers ? GRApiManager.extract_client_ip(request) : request.ip
          unless rate_limiter.allow?(client_ip)
            remaining_reset = rate_limiter.window_seconds
            headers 'Retry-After'               => remaining_reset.to_s,
                    'X-RateLimit-Limit'         => rate_limiter.max_requests.to_s,
                    'X-RateLimit-Remaining'     => '0',
                    'X-RateLimit-Reset'         => (Time.now.to_i + remaining_reset).to_s
            halt 429, { error: "Too many requests", retry_after_seconds: remaining_reset }.to_json
          end
          # Add rate-limit headers on allowed requests too.
          headers 'X-RateLimit-Limit'     => rate_limiter.max_requests.to_s,
                  'X-RateLimit-Remaining' => rate_limiter.remaining(client_ip).to_s
        end

        # Body size limit (skip for read-only / headerless verbs).
        unless %w[GET DELETE OPTIONS HEAD].include?(request.request_method)
          content_length = request.content_length.to_i
          if content_length > max_body
            halt 413, { error: "Payload too large", max_bytes: max_body }.to_json
          end
        end

        content_type :json
      end

      app.options '*' do
        halt 200
      end

      app.not_found do
        status 404
        content_type :json
        { error: "Endpoint not found", path: request.path_info }.to_json
      end

      app.error do
        e = env['sinatra.error']
        status 500
        content_type :json
        if settings.dev_mode
          { error: "Internal Server Error", details: e&.message,
            class: e&.class&.to_s, backtrace: e&.backtrace&.first(15) }.to_json
        else
          { error: "Internal Server Error", details: e&.message }.to_json
        end
      end
    end

    public

    # Dynamically generate routing methods (get, post, put, patch, delete).
    %w[get post put patch delete].each do |verb|
      define_method(verb) do |path, options = {}, &block|
        register_route(verb, path, options, &block)
      end
    end

    # Core routing logic: auth validation, body parsing, param merging, validation, execution.
    def register_route(verb, path, options = {}, &block)
      verb_up         = verb.to_s.upcase
      require_auth    = options.fetch(:auth, true)
      required_params = options.fetch(:requires, nil)

      # Construct the full path with the optional prefix.
      full_path = File.join('/', @prefix.to_s, path.to_s).gsub(%r{/+}, '/')

      handler = proc do
        # 1. Authentication check
        jwt_user = nil
        if require_auth
          auth_header = request.env["HTTP_AUTHORIZATION"]
          halt 401, { error: "Token required. Format: 'Bearer <token>'" }.to_json if auth_header.nil?

          raw_token = auth_header.split(" ").last

          if require_auth == :jwt || (require_auth == true && settings.jwt_secret && settings.token.nil?)
            # JWT authentication mode
            halt 500, { error: "Server error: jwt_secret is not configured" }.to_json unless settings.jwt_secret
            begin
              jwt_user = GRApiManager::JWT.decode(raw_token, settings.jwt_secret)
            rescue GRApiManager::JWT::DecodeError => e
              halt 401, { error: "Invalid token: #{e.message}" }.to_json
            end
          else
            # Static Bearer Token mode
            if raw_token != settings.token
              # Fallback: if jwt_secret is set, try JWT decoding
              if settings.jwt_secret
                begin
                  jwt_user = GRApiManager::JWT.decode(raw_token, settings.jwt_secret)
                rescue GRApiManager::JWT::DecodeError
                  halt 403, { error: "Invalid token" }.to_json
                end
              else
                halt 403, { error: "Invalid token" }.to_json
              end
            end
          end
        end

        # 2. Body parsing — smart detection based on Content-Type
        parsed_body = {}
        if %w[POST PUT PATCH].include?(verb_up)
          begin
            parsed_body = GRApiManager::BodyParser.parse(request)
          rescue ArgumentError => e
            halt 400, { error: e.message }.to_json
          end
        end

        # 3. Merge query/path parameters with parsed body.
        url_params  = smart_parse(params.reject { |_, v| v.is_a?(Hash) && v.key?(:tempfile) })
        all_params  = url_params.merge(parsed_body)

        # Inyect JWT payload if authenticated via JWT
        if jwt_user
          all_params[:current_user] = jwt_user
          all_params[:jwt_payload]  = jwt_user
        end

        # 4. Declarative parameter validation (Array of keys or Hash schema)
        if required_params.is_a?(Hash)
          is_valid, errors = GRApiManager::Validator.validate(all_params, required_params)
          unless is_valid
            status 400
            log_request(verb_up, full_path, 400)
            next { error: "Validation failed", errors: errors }.to_json
          end
        elsif required_params.is_a?(Array) && required_params.any?
          missing = required_params.select do |p|
            val = all_params[p.to_sym]
            val.nil? || (val.is_a?(String) && val.strip.empty?)
          end

          if missing.any?
            status 400
            log_request(verb_up, full_path, 400)
            next { error: "Missing required parameters", required: missing }.to_json
          end
        end

        # 5. Execute user-defined block
        result = instance_exec(all_params, &block)
        log_request(verb_up, full_path, response.status)

        result.is_a?(String) ? result : result.to_json
      end

      @app_class.send(verb.downcase, full_path, &handler)
    end

    # Starts the Sinatra server.
    def run!(workers: nil, threads: '2:8')
      w            = (workers || ENV.fetch('WEB_CONCURRENCY', 2)).to_i
      min_t, max_t = threads.to_s.split(':').map(&:to_i)
      max_t        ||= min_t
      mb           = (@max_body_size.to_f / 1_048_576).round(1)

      # Use Puma as the application server for concurrency.
      @app_class.set :server, :puma
      @app_class.set :server_settings, {
        workers:     w,
        min_threads: min_t,
        max_threads: max_t
      }

      # Background thread to purge stale rate-limit entries.
      if @rate_limiter
        rl = @rate_limiter
        Thread.new do
          loop do
            sleep rl.window_seconds * 2
            rl.cleanup!
          end
        end
      end

      rl_info = if @rate_limiter
                  "#{@rate_limiter.max_requests} req / #{@rate_limiter.window_seconds}s per IP"
                else
                  'Disabled'
                end

      auth_info = []
      auth_info << "Bearer Token" if @token
      auth_info << "JWT (HS256)" if @jwt_secret
      auth_display = auth_info.empty? ? "Public (no token)" : auth_info.join(' + ')

      puts "============================================="
      puts "  GR API MANAGER STARTED"
      puts "  Port      : #{@port}"
      puts "  Auth      : #{auth_display}"
      puts "  Prefix    : #{@prefix.empty? ? '/' : @prefix}"
      puts "  Max Body  : #{mb} MB"
      puts "  Workers   : #{w}  |  Threads: #{min_t}:#{max_t}"
      puts "  Rate Limit: #{rl_info}"
      puts "  Dev Mode  : #{@dev_mode ? 'ON  ⚠️  (disable in production)' : 'Off'}"
      puts "============================================="
      @app_class.run!
    end
  end
end