require 'sinatra/base'
require 'json'
require 'dotenv/load'

module ApiManager
  class NewApi
    attr_reader :app_class

    # Se agregó :prefix para versionamiento (ej. '/api/v1')
    def initialize(port: nil, bearer_token: nil, permitted_hosts: [], prefix: '')
      @port = port || ENV['PORT'] || 4000
      @token = bearer_token || ENV['API_TOKEN']
      @permitted_hosts = permitted_hosts.empty? ? [] : permitted_hosts
      @prefix = prefix
      
      @app_class = Class.new(Sinatra::Base) do
        def log_request(method, path, params, status_code)
          color = status_code.between?(200, 299) ? "\e[32m" : "\e[31m"
          puts "[#{Time.now.strftime('%H:%M:%S')}] #{color}#{method} #{path} - #{status_code}\e[0m"
        end

        # Convierte strings de URL a tipos reales ("10" -> 10, "true" -> true)
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

    def configure_app
      app = @app_class
      app.set :port, @port
      app.set :bind, '0.0.0.0'
      app.set :token, @token
      app.set :show_exceptions, false 
      app.set :host_authorization, { permitted_hosts: @permitted_hosts }

      # Manejo de CORS y Preflight (Bulletproof)
      app.before do
        headers 'Access-Control-Allow-Origin' => '*',
                'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
        content_type :json
      end

      # Intercepta todas las peticiones OPTIONS para frontends
      app.options '*' do
        halt 200
      end

      # 404 Global JSON
      app.not_found do
        status 404
        { error: "Endpoint no encontrado", path: request.path_info }.to_json
      end

      # 500 Global JSON
      app.error do
        e = env['sinatra.error']
        status 500
        { error: "Error interno del servidor", details: e.message }.to_json
      end
    end

    public

    %w[get post put delete].each do |verb|
      define_method(verb) do |path, options = {}, &block|
        newMethod(verb, path, options, &block)
      end
    end

    def newMethod(verb, path, options = {}, &block)
      verb = verb.to_s.upcase
      require_auth = options.fetch(:auth, true)
      required_params = options.fetch(:requires, [])
      
      # Aplicamos el prefijo a la ruta (ej. '/api/v1' + '/users')
      full_path = File.join('/', @prefix.to_s, path.to_s).gsub(%r{/+}, '/')

      handler = proc do
        # 1. Seguridad
        if require_auth
          auth_header = request.env["HTTP_AUTHORIZATION"]
          halt 401, { error: "Token requerido. Formato: 'Bearer <token>'" }.to_json if auth_header.nil?
          halt 403, { error: "Token inválido" }.to_json if auth_header.split(" ").last != settings.token
        end

        # 2. Parseo Inteligente
        parsed_body = {}
        if ['POST', 'PUT'].include?(verb)
          cuerpo = request.body.read.to_s
          unless cuerpo.empty?
            begin
              parsed_body = JSON.parse(cuerpo, symbolize_names: true)
            rescue JSON::ParserError
              halt 400, { error: "Cuerpo de petición no es un JSON válido" }.to_json
            end
          end
        end

        # Unimos params de URL (convertidos a sus tipos reales) y el body
        all_params = smart_parse(params).merge(parsed_body)

        # 3. Validación Declarativa
        missing = required_params.select { |p| all_params[p.to_sym].nil? || all_params[p.to_sym].to_s.strip.empty? }
        if missing.any?
          status 400
          log_request(verb, full_path, all_params, 400)
          next { error: "Faltan parámetros obligatorios", required: missing }.to_json
        end

        # 4. Ejecución
        result = instance_exec(all_params, &block)
        log_request(verb, full_path, all_params, response.status)
        result.to_json
      end

      # Registramos en Sinatra
      @app_class.send(verb.downcase, full_path, &handler)
    end

    def run!
      puts "============================================="
      puts "API MANAGER INICIADO"
      puts "Puerto : #{@port}"
      puts "Auth   : #{@token ? 'Requerida por defecto' : 'Pública'}"
      puts "Prefix : #{@prefix.empty? ? '/' : @prefix}"
      puts "============================================="
      @app_class.run!
    end
  end
end