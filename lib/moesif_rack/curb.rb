require 'curb'
require_relative '../../moesif_capture_outgoing/httplog.rb'

class Curl::Easy
  include Moesif::Curb::Easy
end
