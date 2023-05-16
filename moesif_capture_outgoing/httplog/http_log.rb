require 'rack'
require 'moesif_api'
require 'json'
require 'base64'
require_relative '../../lib/moesif_rack/app_config.rb'

module MoesifCaptureOutgoing
  class << self
    def start_capture_outgoing(options)
      @moesif_options = options
      if not @moesif_options['application_id']
        raise 'application_id required for Moesif Middleware'
      end
      @api_client = MoesifApi::MoesifAPIClient.new(@moesif_options['application_id'])
      @api_controller = @api_client.api
      @debug = @moesif_options['debug']
      @get_metadata_outgoing = @moesif_options['get_metadata_outgoing']
      @identify_user_outgoing = @moesif_options['identify_user_outgoing']
      @identify_company_outgoing = @moesif_options['identify_company_outgoing']
      @identify_session_outgoing = @moesif_options['identify_session_outgoing']
      @skip_outgoing = options['skip_outgoing']
      @mask_data_outgoing = options['mask_data_outgoing']
      @log_body_outgoing = options.fetch('log_body_outgoing', true)
      @app_config = AppConfig.new(@debug)
      @config_etag = nil
      @sampling_percentage = 100
      @last_updated_time = Time.now.utc
      @config_dict = Hash.new
      begin
        new_config = @app_config.get_config(@api_controller)
        if !new_config.nil?
          @config, @config_etag, @last_config_download_time = @app_config.parse_configuration(new_config)
        end
      rescue => exception
        if @debug
          puts 'Error while parsing application configuration on initialization'
          puts exception.to_s
        end
      end
    end

    def call adapter
      send_moesif_event adapter
    end
    
    def get_response_body(response)
      body = response.respond_to?(:body) ? response.body : response
      body = body.inject("") { |i, a| i << a } if body.respond_to?(:each)
      body.to_s
    end

    def send_moesif_event adapter
      if adapter.moesif_event?
        puts 'Skip sending as it is moesif Event' if @debug
        return
      end

      if true
        request_model = adapter.request.to_event_request_model log_body: @log_body_outgoing
        response_model = adapter.response.to_event_response_model log_body: @log_body_outgoing

        # Prepare Event Model
        event_model = MoesifApi::EventModel.new
        event_model.request = request_model
        event_model.response = response_model
        event_model.direction = "Outgoing"

        # Metadata for Outgoing Request
        if @get_metadata_outgoing
          if @debug
            puts "calling get_metadata_outgoing proc"
          end
          event_model.metadata = @get_metadata_outgoing.call(adapter.base_request, adapter.base_response)
        end

        # Identify User
        if @identify_user_outgoing
          if @debug
            puts "calling identify_user_outgoing proc"
          end
          event_model.user_id = @identify_user_outgoing.call(adapter.base_request, adapter.base_response)
        end

        # Identify Company
        if @identify_company_outgoing
          if @debug
            puts "calling identify_company_outgoing proc"
          end
          event_model.company_id = @identify_company_outgoing.call(adapter.base_request, adapter.base_response)
        end

        # Session Token
        if @identify_session_outgoing
          if @debug
            puts "calling identify_session_outgoing proc"
          end
          event_model.session_token = @identify_session_outgoing.call(adapter.base_request, adapter.base_response)
        end

        # Skip Outgoing Request
        should_skip = false

        if @skip_outgoing
          if @skip_outgoing.call(adapter.base_request, adapter.base_response)
            should_skip = true;
          end
        end

        if !should_skip

          # Mask outgoing Event
          if @mask_data_outgoing
            if @debug
              puts "calling mask_data_outgoing proc"
            end
            event_model = @mask_data_outgoing.call(event_model)
          end

          # Send Event to Moesif
          begin
            @random_percentage = Random.rand(0.00..100.00)
            begin 
              @sampling_percentage = @app_config.get_sampling_percentage(event_model, @config, event_model.user_id, event_model.company_id)
            rescue => exception
              if @debug
                puts 'Error while getting sampling percentage, assuming default behavior'
                puts exception.to_s
              end
              @sampling_percentage = 100
            end

            if @sampling_percentage > @random_percentage
              event_model.weight = @app_config.calculate_weight(@sampling_percentage)
              if @debug
                puts 'Sending Outgoing Request Data to Moesif'
                puts event_model.to_json
              end
              event_api_response = @api_controller.create_event(event_model)
              event_response_config_etag = event_api_response[:x_moesif_config_etag]

              if !event_response_config_etag.nil? && !@config_etag.nil? && @config_etag != event_response_config_etag && Time.now.utc > @last_updated_time + 300
                begin 
                  new_config = @app_config.get_config(@api_controller)
                  if !new_config.nil?
                    @config, @config_etag, @last_config_download_time = @app_config.parse_configuration(new_config)
                  end
                rescue => exception
                  if @debug
                    puts 'Error while updating the application configuration'
                    puts exception.to_s
                  end
                end
              end
              if @debug
                puts("Event successfully sent to Moesif")
              end
            else
              if @debug
                puts("Skipped outgoing Event due to sampling percentage: " + @sampling_percentage.to_s + " and random percentage: " + @random_percentage.to_s)
              end
            end
          rescue MoesifApi::APIException => e
            if e.response_code.between?(401, 403)
              puts "Unathorized accesss sending event to Moesif. Please verify your Application Id."
            end
            if @debug
              puts "Error sending event to Moesif, with status code: "
              puts e.response_code
            end
          rescue => e
            if @debug
                puts e.to_s
            end
          end
        else 
          if @debug
            puts 'Skip sending outgoing request'
          end 
        end
      end
    end
  end
end
