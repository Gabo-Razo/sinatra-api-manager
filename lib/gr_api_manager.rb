require 'sinatra/base'
require 'json'
require 'dotenv/load'

module GRApiManager
  class Server
    attr_reader :app_class

    # Initializes the server configuration.
    def initialize(port: nil, bearer_token: nil, permitted_hosts: [], prefix: '')
      @port = port || ENV['PORT'] || 4000
      @token = bearer_token || ENV['API_TOKEN']
      @permitted_hosts = permitted_hosts.empty? ? [] : permitted_hosts
      @prefix = prefix
      
      @app_class = Class.new(Sinatra::Base) do
        
        # Logs HTTP requests with status-based color coding.
        def log_request(method, path, params, status_code)
          color = status_code.between?(200, 299) ? "\e[32m" : "\e[31m"
          puts "[#{Time.now.strftime('%H:%M:%S')}] #{color}#{method} #{path} - #{status_code}\e[0m"
        end

        # Casts string URL parameters to native Ruby types (Integer, Float, Boolean).
        def smart_parse(hash)
          hash.transform_values do |val|
            case val
            when 'true' then true
            when 'false' then false
            when /^[0-9]+$/ then val.to_i
            when /^[0-9]+\.[0-9]+$/ then val.to_f
            else val
            end
          end
        end
      end

      configure_app
    end

    private

    # Sets up Sinatra environment, CORS policies, and global error handlers.
    def configure_app
      app = @app_class
      app.set :port, @port
      app.set :bind, '0.0.0.0'
      app.set :token, @token
      app.set :show_exceptions, false 
      app.set :host_authorization, { permitted_hosts: @permitted_hosts }

      # Enable broad CORS and handle preflight requests.
      app.before do
        headers 'Access-Control-Allow-Origin' => '*',
                'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
        content_type :json
      end

      app.options '*' do
        halt 200
      end

      # JSON formatted 404 response.
      app.not_found do
        status 404
        { error: "Endpoint not found", path: request.path_info }.to_json
      end

      # JSON formatted 500 response.
      app.error do
        e = env['sinatra.error']
        status 500
        { error: "Internal Server Error", details: e.message }.to_json
      end
    end

    public

    # Dynamically generate routing methods (get, post, put, delete).
    %w[get post put delete].each do |verb|
      define_method(verb) do |path, options = {}, &block|
        register_route(verb, path, options, &block)
      end
    end

    # Core routing logic: auth validation, param parsing, and block execution.
    def register_route(verb, path, options = {}, &block)
      verb = verb.to_s.upcase
      require_auth = options.fetch(:auth, true)
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

        # 2. Body parsing (for POST/PUT requests)
        parsed_body = {}
        if ['POST', 'PUT'].include?(verb)
          body_data = request.body.read.to_s
          unless body_data.empty?
            begin
              parsed_body = JSON.parse(body_data, symbolize_names: true)
            rescue JSON::ParserError
              halt 400, { error: "Invalid JSON body" }.to_json
            end
          end
        end

        # 3. Merge query parameters with parsed JSON body
        all_params = smart_parse(params).merge(parsed_body)

        # 4. Declarative parameter validation
        missing = required_params.select { |p| all_params[p.to_sym].nil? || all_params[p.to_sym].to_s.strip.empty? }
        if missing.any?
          status 400
          log_request(verb, full_path, all_params, 400)
          next { error: "Missing required parameters", required: missing }.to_json
        end

        # 5. Execute user-defined block
        result = instance_exec(all_params, &block)
        log_request(verb, full_path, all_params, response.status)
        result.to_json
      end

      @app_class.send(verb.downcase, full_path, &handler)
    end

    # Starts the Sinatra server with a custom GR banner.
    def run!
      puts "============================================="
      puts "  GR API MANAGER STARTED"
      puts "  Port   : #{@port}"
      puts "  Auth   : #{@token ? 'Enabled' : 'Public'}"
      puts "  Prefix : #{@prefix.empty? ? '/' : @prefix}"
      puts "============================================="
      @app_class.run!
    end
  end
end