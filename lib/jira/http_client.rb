require 'json'
require 'net/https'
require 'net/http/post/multipart'
require 'cgi/cookie'

module JIRA
  class HttpClient < RequestClient

    DEFAULT_OPTIONS = {
      :username           => '',
      :password           => ''
    }

    attr_reader :options

    def initialize(options)
      @options = DEFAULT_OPTIONS.merge(options)
      @cookies = {}
    end

    def make_cookie_auth_request
      body = { :username => @options[:username], :password => @options[:password] }.to_json
      make_request(:post, '/rest/auth/1/session', body, {'Content-Type' => 'application/json'})
    end

    def make_request(http_method, path, body='', headers={})
      if http_method == :upload
        # Add Atlassian XSRF check bypass header
        headers.merge! 'X-Atlassian-Token' => 'nocheck'

        # XXX: should we raise an exception if file param is blank?
        # XXX: should we detect mime type if none provided?
        # Set filename if none set by caller
        body['filename'] ||= File.basename body['content']

        request = Net::HTTP::Post::Multipart.new(path, { 'file' => UploadIO.new(body['content'], body['type'], body['filename']) }, headers)
      else
        request = Net::HTTP.const_get(http_method.to_s.capitalize).new(path, headers)
        request.body = body unless body.nil?
      end
      add_cookies(request) if options[:use_cookies]

      request.basic_auth(@options[:username], @options[:password])
      response = basic_auth_http_conn.request(request)
      store_cookies(response) if options[:use_cookies]
      response
    end

    def basic_auth_http_conn
      http_conn(uri)
    end

    def http_conn(uri)
      if @options[:proxy_address]
          http_class = Net::HTTP::Proxy(@options[:proxy_address], @options[:proxy_port] ? @options[:proxy_port] : 80)
      else
          http_class = Net::HTTP
      end
      http_conn = http_class.new(uri.host, uri.port)
      http_conn.use_ssl = @options[:use_ssl]
      http_conn.verify_mode = @options[:ssl_verify_mode]
      http_conn.read_timeout = @options[:read_timeout]
      http_conn
    end

    def uri
      uri = URI.parse(@options[:site])
    end

    private

    def store_cookies(response)
      cookies = response.get_fields('set-cookie')
      if cookies
        cookies.each do |cookie|
          data = CGI::Cookie.parse(cookie)
          data.delete('Path')
          @cookies.merge!(data)
        end
      end
    end

    def add_cookies(request)
      cookie_array = @cookies.values.map { |cookie| cookie.to_s }
      request.add_field('Cookie', cookie_array.join('; ')) if cookie_array.any?
      request
    end
  end
end
