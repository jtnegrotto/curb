require 'curb'

module Moesif
  module Curb
    module Easy
      class Adapter < MoesifCaptureOutgoing::AbstractAdapter
        attr_reader :curl, :url, :request, :request_time, :response, :response_time
        alias_method :base_request, :request
        alias_method :base_response, :response

        def self.call *args
          new(*args).call
        end

        def initialize curl, method, request_time, response_time
          @curl = curl
          @url = curl.url
          @request = Request.new curl, method, request_time, url
          @response = Response.new curl, response_time
          @request_time = request_time
          @response_time = response_time
        end

        def call
          MoesifCaptureOutgoing.call self
        end

        class Request < MoesifCaptureOutgoing::AbstractAdapter::AbstractRequest
          attr_reader :curl, :method, :time, :url

          def initialize curl, method, time, url
            @curl = curl
            @method = method
            @time = time
            @url = url
          end

          def body
            curl.post_body
          end

          def each_header
            return headers.each unless block_given?
            headers.each do |key, value|
              yield key, value
            end
          end

          def headers
            curl.headers.transform_values do |value|
              case value
              when Array
                value.join(', ')
              else
                String(value)
              end
            end
          end
        end

        class Response < MoesifCaptureOutgoing::AbstractAdapter::AbstractResponse
          CRLF = "\r\n"
          HEADER_SEPARATOR = ':'
          VALUE_PATTERN = /^[ \t]*(?<content>.*?)[ \t]*$/

          attr_reader :curl, :time

          def initialize curl, time
            @curl = curl
            @time = time
          end

          def code
            curl.response_code
          end

          def body
            curl.body_str
          end

          def each_header
            return headers.each unless block_given?
            headers.each do |key, value|
              yield key, value
            end
          end

          def headers
            # cURL only provides us with the raw header section, so we get to
            # parse it ourselves. We're ignoring obsolete folding syntax here,
            # and other minutiae of the spec, so it's not totally compliant,
            # but should be close enough for now.

            header_strings = curl.header_str
              .split(CRLF, 2).last          # Disregard start line
              .chomp(CRLF)                  # Disregard trailing CRLF
              .each_line(CRLF, chomp: true) # Get each header line

            header_strings
              .each_with_object(Hash.new { |h, k| h[k] = Array.new }) { |line, hsh|
                name, value = line.split HEADER_SEPARATOR, 2

                # Remove optional whitespace from value
                value = value[VALUE_PATTERN, :content]

                # Use preexisting key, if any
                key = hsh.keys.find(-> { name }) { _1.casecmp? name }

                hsh[key] << value
              }.transform_values { |value|
                case value
                when Array
                  value.join ', '
                else
                  String(value)
                end
              }
          end
        end
      end

      REQUEST_METHODS = [:http_post => :post]

      class << self
        def included base
          REQUEST_METHODS.each do |meth|
            if meth.is_a? Hash
              meth.each do |meth, aliases|
                define_original_alias base, meth
                redefine_request_method base, meth
                redefine_request_method_aliases base, meth, aliases
                redefine_perform base
              end
            else
              define_original_alias base, meth
              redefine_request_method base, meth
            end
          end
        end

        def define_original_alias base, meth
          orig_alias_name = "orig_#{meth}".to_sym
          base.class_eval do
            alias_method orig_alias_name, meth
          end
        end

        def redefine_request_method base, meth
          base.class_eval do
            define_method meth do |*args|
              method = meth[/^http_(?<method>[a-z]+)$/, :method]
              start_time = Time.now.utc.iso8601(3)
              res = public_send("orig_#{meth}", *args)
              end_time = Time.now.utc.iso8601(3)
              Adapter.call self, method, start_time, end_time
              res
            end
          end
        end

        def redefine_request_method_aliases base, meth, aliases
          base.class_eval do
            Array(aliases).each do |existing_alias|
              alias_method existing_alias, meth
            end
          end
        end

        def redefine_perform base
          base.class_eval do
            alias_method :orig_perform, :perform

            def perform *args
              start_time = Time.now.utc.iso8601(3)
              res = orig_perform(*args)
              end_time = Time.now.utc.iso8601(3)
              Adapter.call self, 'get', start_time, end_time
              res
            end
          end
        end
      end
    end
  end
end