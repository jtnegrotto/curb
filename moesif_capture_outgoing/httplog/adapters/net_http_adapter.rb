require 'time'
require 'net/http'

module MoesifCaptureOutgoing
  class NetHTTPAdapter < AbstractAdapter
    def initialize request, response
      @request = request
      @response = response
    end

    def base_request
      request.net_http_request
    end

    def base_response
      response.net_http_response
    end

    class Request < AbstractRequest
      attr_reader :net_http_request, :url, :time

      def initialize url, net_http_request, time
        @url = url
        @net_http_request = net_http_request
        @time = time
      end

      def body
        @body ||= net_http_request.body
      end

      def headers
        net_http_request.each_header.collect.to_h
      end

      def method
        net_http_request.method.to_s.upcase
      end
    end

    class Response < AbstractResponse
      attr_reader :net_http_response, :time

      def initialize net_http_response, time
        @net_http_response = net_http_response
        @time = time
      end

      def code
        @code ||= net_http_response.code.then { |val|
          val.is_a?(Symbol) ? transform_response_code(val) : val
        }.to_i
      end

      def body
        @body ||= get_body
      end

      def headers
        net_http_response.each_header.collect.to_h
      end

      private

      def transform_response_code response_code_name
        Rack::Utils::HTTP_STATUS_CODES.detect { |_k, v| v.to_s.casecmp(response_code_name.to_s).zero? }.first
      end

      def get_body
        body = net_http_response.respond_to? :body ? net_http_response.body : net_http_response
        body = body.inject('') { |i, a| i << a } if body.respond_to?(:each)
        body.to_s
      end
    end

    module Hook
      def self.included base
        base.class_eval do
          unless method_defined? :request_without_moesif
            alias_method :request_without_moesif, :request
          end

          def request(request, body = nil, &block)
            # Request Start Time
            request_time = Time.now.utc.iso8601(3)
            
            # URL
            url = "https://#{@address}#{request.path}"

            # Response
            @response = request_without_moesif request, body, &block

            # Response Time
            response_time = Time.now.utc.iso8601(3)
      
            # Log Event to Moesif
            if started?
              wrapped_request = Request.new url, request, request_time
              wrapped_response = Response.new @response, response_time
              adapter = NetHTTPAdapter.new wrapped_request, wrapped_response
              MoesifCaptureOutgoing.call adapter
            end
      
            @response
          end
        end
      end
    end
  end
end

class Net::HTTP
  include MoesifCaptureOutgoing::NetHTTPAdapter::Hook
end