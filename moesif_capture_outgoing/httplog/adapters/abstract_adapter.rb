module MoesifCaptureOutgoing
  class AbstractAdapter
    attr_reader :request, :response

    %i(base_request base_response).each do |interface_method|
      define_method interface_method do |*args|
        raise NotImplementedError, "#{self.class.name}##{__method__} is not implemented"
      end
    end

    class AbstractRequest
      %i(url method headers body time).each do |interface_method|
        define_method interface_method do |*args|
          raise NotImplementedError, "#{self.class.name}##{__method__} is not implemented"
        end
      end

      def body?
        !body.nil? && !body.empty?
      end

      def event_model_body
        return unless body?

        @event_body ||= body.then { |val|
          begin
            JSON.parse(body)
          rescue
            @event_model_body_transfer_encoding = 'base64'
            Base64.encode64(body)
          end
        }
      end

      def event_model_body_transfer_encoding
        # call #event_model_body to ensure @event_model_body_transfer_encoding is set
        event_model_body
        @event_model_body_transfer_encoding
      end

      def to_event_request_model log_body: false
        MoesifApi::EventRequestModel.new.tap do |model|
          model.time = time
          model.uri = url
          model.verb = method.to_s.upcase
          model.headers = headers
          model.api_version = nil
          if log_body && body?
            model.body = event_model_body
            model.transfer_encoding = event_model_body_transfer_encoding
          end
        end
      end
    end

    class AbstractResponse
      %i(code body headers).each do |interface_method|
        define_method interface_method do |*args|
          raise NotImplementedError, "#{self.class.name}##{__method__} is not implemented"
        end
      end

      def body?
        !body.nil? && !body.empty?
      end

      def event_model_body
        return unless body?

        @event_model_body ||= body.then { |val|
          begin
            JSON.parse(body)
          rescue
            @event_model_body_transfer_encoding = 'base64'
            Base64.encode64(body)
          end
        }
      end

      def event_model_body_transfer_encoding
        # call #event_model_body to ensure @event_model_body_transfer_encoding is set
        event_model_body
        @event_model_body_transfer_encoding
      end

      def to_event_response_model log_body: false
        MoesifApi::EventResponseModel.new.tap do |model|
          model.time = time
          model.status = code
          model.headers = headers
          if log_body && body?
            model.body = event_model_body
            model.transfer_encoding = event_model_body_transfer_encoding
          end
        end
      end
    end

    def moesif_event?
      request.url.downcase.include? 'moesif'
    end
  end
end