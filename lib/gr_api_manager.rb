require 'sinatra/base'
require 'json'
require 'dotenv/load'
require 'base64'
require 'tempfile'

module GRApiManager
  # Convenience size helpers — use in max_body_size:
  #   GRApiManager.mb(50)   => 50 MB in bytes
  #   GRApiManager.gb(2)    => 2 GB in bytes
  def self.mb(n) = n * 1_024 * 1_024
  def self.gb(n) = n * 1_024 * 1_024 * 1_024

  # ---------------------------------------------------------------------------
  # RateLimiter — thread-safe sliding-window rate limiter per IP address.
  #
  # Prevents any single client from flooding the server. Uses a mutex-protected
  # in-memory store with automatic cleanup to avoid unbounded memory growth.
  # ---------------------------------------------------------------------------
  class RateLimiter
    attr_reader :max_requests, :window_seconds

    def initialize(max_requests:, window_seconds:)
      @max    = max_requests
      @window = window_seconds
      @store  = Hash.new { |h, k| h[k] = [] }
      @mutex  = Mutex.new
    end

    # Returns true if the request from *ip* is within the allowed rate.
    # Increments the counter for that IP on each allowed request.
    def allow?(ip)
      @mutex.synchronize do
        now    = Time.now.to_f
        cutoff = now - @window
        @store[ip].reject! { |t| t < cutoff }
        return false if @store[ip].size >= @max
        @store[ip] << now
        true
      end
    end

    # Remaining requests allowed for *ip* in the current window.
    def remaining(ip)
      @mutex.synchronize do
        cutoff = Time.now.to_f - @window
        active = @store[ip].count { |t| t >= cutoff }
        [@max - active, 0].max
      end
    end

    # Removes stale entries — call periodically to prevent memory growth.
    def cleanup!
      @mutex.synchronize do
        cutoff = Time.now.to_f - @window
        @store.each_value { |times| times.reject! { |t| t < cutoff } }
        @store.delete_if  { |_, times| times.empty? }
      end
    end

    # Summary hash — safe to log or expose on a diagnostic endpoint.
    def stats
      @mutex.synchronize do
        { tracked_ips: @store.size, max_requests: @max, window_seconds: @window }
      end
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
      @size         = tempfile.respond_to?(:size) ? tempfile.size : tempfile.length
    end

    # Returns the raw binary content of the file as a String (encoding: BINARY).
    def read
      if @tempfile.respond_to?(:read)
        @tempfile.rewind
        @tempfile.read
      else
        @tempfile.to_s.force_encoding(Encoding::BINARY)
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
  #
  # Supported formats:
  #   application/json                 -> Hash (symbolized keys)
  #   multipart/form-data              -> Hash + :_files key (FilePayload objects)
  #   application/octet-stream         -> :_raw_binary (FilePayload)
  #   image/*  / application/pdf etc.  -> :_raw_binary (FilePayload)
  #   text/plain                       -> :_raw_text (String)
  #   application/x-www-form-urlencoded-> Hash (Sinatra already handles this)
  # ---------------------------------------------------------------------------
  module BodyParser

    BINARY_MIME_PREFIXES = %w[
      image/ video/ audio/ application/pdf application/msword
      application/vnd. application/zip application/x-tar
      application/x-rar application/octet-stream
    ].freeze

    # Returns a Hash of parsed body values.
    # Special keys injected into the result hash:
    #   :_files        => { field_name => FilePayload }  (multipart)
    #   :_raw_binary   => FilePayload                    (raw binary body)
    #   :_raw_text     => String                         (plain-text body)
    def self.parse(request)
      content_type = (request.content_type || '').split(';').first.strip.downcase

      case content_type
      when 'application/json'
        parse_json(request)

      when 'multipart/form-data'
        parse_multipart(request)

      when 'application/x-www-form-urlencoded'
        # Sinatra already exposes these in `params` — nothing extra to do.
        {}

      when 'text/plain'
        text = request.body.read.to_s.force_encoding(Encoding::UTF_8)
        { _raw_text: text }

      else
        # Treat anything else that looks binary as a raw binary upload.
        if binary_content_type?(content_type)
          parse_raw_binary(request, content_type)
        else
          # Last resort: try JSON, silently fall back to empty hash.
          parse_json(request) rescue {}
        end
      end
    end

    # -------------------------------------------------------------------------
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
          # Rack multipart file upload hash
          files[sym] = FilePayload.new(
            tempfile:     value[:tempfile],
            filename:     value[:filename] || key,
            content_type: value[:type] || 'application/octet-stream'
          )
        elsif value.is_a?(Array)
          # Multiple file inputs with the same name
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

      # Try to derive a filename from the Content-Disposition header, if any.
      disposition = request.env['HTTP_CONTENT_DISPOSITION'] || ''
      filename    = disposition[/filename="?([^";]+)"?/, 1] || "upload#{ext_for(content_type)}"

      # Wrap the raw bytes in a StringIO so FilePayload can rewind/read it.
      io = StringIO.new(raw.force_encoding(Encoding::BINARY))
      io.define_singleton_method(:size) { raw.bytesize }

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

    # Maps common MIME types to file extensions for unnamed raw uploads.
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
  # Server — the public-facing DSL.
  # ---------------------------------------------------------------------------
  class Server
    attr_reader :app_class

    # Initializes the server configuration.
    #
    # Options:
    #   port:               Integer  – listening port (default: ENV['PORT'] || 4000)
    #   bearer_token:       String   – Bearer token for auth (default: ENV['API_TOKEN'])
    #   permitted_hosts:    Array    – host allowlist; empty = allow all
    #   prefix:             String   – route prefix, e.g. '/api/v1'
    #   max_body_size:      Integer  – maximum accepted body in bytes (default: 50 MB)
    #   dev_mode:           Boolean  – show full stack traces on 500 (default: false)
    #   rate_limit:         Integer  – max requests per IP per window (nil = disabled)
    #   rate_limit_window:  Integer  – sliding window in seconds (default: 60)
    def initialize(
      port: nil,
      bearer_token: nil,
      permitted_hosts: [],
      prefix: '',
      max_body_size:      GRApiManager.mb(50),
      dev_mode:           false,
      rate_limit:         nil,
      rate_limit_window:  60
    )
      @port            = port || ENV['PORT'] || 4000
      @token           = bearer_token || ENV['API_TOKEN']
      @permitted_hosts = permitted_hosts.empty? ? [] : permitted_hosts
      @prefix          = prefix
      @max_body_size   = max_body_size
      @dev_mode        = dev_mode
      @rate_limiter    = rate_limit ? GRApiManager::RateLimiter.new(
                           max_requests:   rate_limit,
                           window_seconds: rate_limit_window
                         ) : nil

      @app_class = Class.new(Sinatra::Base) do

        # Logs HTTP requests with status-based color coding.
        def log_request(method, path, status_code)
          color = status_code.between?(200, 299) ? "\e[32m" : "\e[31m"
          puts "[#{Time.now.strftime('%H:%M:%S')}] #{color}#{method} #{path} - #{status_code}\e[0m"
        end

        # Casts string URL parameters to native Ruby types (Integer, Float, Boolean).
        # Leaves values untouched if they are already non-String (e.g. FilePayload).
        def smart_parse(hash)
          hash.transform_values do |val|
            next val unless val.is_a?(String)
            case val
            when 'true'            then true
            when 'false'           then false
            when /^\d+$/           then val.to_i
            when /^\d+\.\d+$/      then val.to_f
            else val
            end
          end
        end
      end

      configure_app
    end

    private

    # Sets up Sinatra environment, CORS policies, body size limit, rate limiting, and global error handlers.
    def configure_app
      app           = @app_class
      max_body      = @max_body_size
      rate_limiter  = @rate_limiter

      app.set :port,               @port
      app.set :bind,               '0.0.0.0'
      app.set :token,              @token
      app.set :dev_mode,           @dev_mode
      app.set :show_exceptions,    @dev_mode
      app.set :host_authorization, { permitted_hosts: @permitted_hosts }
      app.enable :static

      app.before do
        headers 'Access-Control-Allow-Origin'  => '*',
                'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization, Content-Disposition'

        # Rate limiting — checked before anything else.
        if rate_limiter
          ip = request.ip
          unless rate_limiter.allow?(ip)
            remaining_reset = rate_limiter.window_seconds
            headers 'Retry-After'               => remaining_reset.to_s,
                    'X-RateLimit-Limit'         => rate_limiter.max_requests.to_s,
                    'X-RateLimit-Remaining'     => '0',
                    'X-RateLimit-Reset'         => (Time.now.to_i + remaining_reset).to_s
            halt 429, { error: "Too many requests", retry_after_seconds: remaining_reset }.to_json
          end
          # Add rate-limit headers on allowed requests too.
          headers 'X-RateLimit-Limit'     => rate_limiter.max_requests.to_s,
                  'X-RateLimit-Remaining' => rate_limiter.remaining(request.ip).to_s
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
        { error: "Endpoint not found", path: request.path_info }.to_json
      end

      app.error do
        e = env['sinatra.error']
        status 500
        if settings.dev_mode
          { error: "Internal Server Error", details: e.message,
            class: e.class.to_s, backtrace: e.backtrace&.first(15) }.to_json
        else
          { error: "Internal Server Error", details: e.message }.to_json
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
    #
    # Supported body formats (auto-detected via Content-Type):
    #   application/json             – standard JSON body
    #   multipart/form-data          – form fields + file uploads
    #   application/octet-stream     – raw binary stream
    #   image/*, video/*, audio/*    – raw binary media
    #   application/pdf, etc.        – raw binary document
    #   text/plain                   – plain text body
    #
    # Inside your block, params will contain:
    #   :_files      => { field: FilePayload }   – for multipart uploads
    #   :_raw_binary => FilePayload              – for raw binary/media bodies
    #   :_raw_text   => String                   – for text/plain bodies
    #
    # Route options:
    #   auth:     Boolean – require Bearer Token (default: true)
    #   requires: Array   – required parameter keys [:name, :email, ...]
    def register_route(verb, path, options = {}, &block)
      verb_up        = verb.to_s.upcase
      require_auth   = options.fetch(:auth, true)
      required_params = options.fetch(:requires, [])

      # Construct the full path with the optional prefix.
      full_path = File.join('/', @prefix.to_s, path.to_s).gsub(%r{/+}, '/')

      handler = proc do
        # 1. Authentication check
        if require_auth
          auth_header = request.env["HTTP_AUTHORIZATION"]
          halt 401, { error: "Token required. Format: 'Bearer <token>'" }.to_json if auth_header.nil?
          halt 403, { error: "Invalid token" }.to_json if auth_header.split(" ").last != settings.token
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
        #    URL params go through smart_parse; body values are left as-is
        #    (so FilePayload objects, arrays, etc. are preserved).
        url_params  = smart_parse(params.reject { |_, v| v.is_a?(Hash) && v.key?(:tempfile) })
        all_params  = url_params.merge(parsed_body)

        # 4. Declarative parameter validation (skips special _ keys and FilePayload values).
        missing = required_params.select do |p|
          val = all_params[p.to_sym]
          val.nil? || (val.is_a?(String) && val.strip.empty?)
        end

        if missing.any?
          status 400
          log_request(verb_up, full_path, 400)
          next { error: "Missing required parameters", required: missing }.to_json
        end

        # 5. Execute user-defined block
        result = instance_exec(all_params, &block)
        log_request(verb_up, full_path, response.status)

        # If the block returned a String (e.g. already rendered binary data),
        # pass it through unchanged. Otherwise serialize to JSON.
        result.is_a?(String) ? result : result.to_json
      end

      @app_class.send(verb.downcase, full_path, &handler)
    end

    # Starts the Sinatra server.
    #
    # Options:
    #   workers: Integer – Puma worker processes (default: ENV['WEB_CONCURRENCY'] || 2)
    #   threads: String  – min:max thread count per worker (default: '2:8')
    #
    # For sustained high traffic, run behind Nginx as a reverse proxy.
    # See the README section "High Traffic & Concurrency" for production tuning.
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

      # Background thread to purge stale rate-limit entries (prevents memory growth).
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

      puts "============================================="
      puts "  GR API MANAGER STARTED"
      puts "  Port      : #{@port}"
      puts "  Auth      : #{@token ? 'Enabled' : 'Public (no token)'}"
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