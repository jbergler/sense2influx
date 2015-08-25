#!/usr/bin/env ruby

require 'faraday'
require 'faraday_middleware'
require 'base64'
require 'json'
require 'influxdb'

SENSE_API = 'https://api.hello.is/'
SENSE_CLIENT_ID = '8d3c1664-05ae-47e4-bcdb-477489590aa4'
SENSE_CLIENT_SECRET = '4f771f6f-5c10-4104-bbc6-3333f5b11bf9'

class Sense
  TOKEN_FILE = File.join(ENV['HOME'], '.sense_token')

  def initialize
    @conn = Faraday.new(:url => SENSE_API) do |faraday|
      faraday.request  :url_encoded
      faraday.response :logger
      faraday.response :json, :content_type => /\bjson$/
      faraday.adapter  Faraday.default_adapter
    end
    get_token
    @conn.authorization :Bearer, @token['access_token']
  end

  def get_token
    return if @token
    @token = JSON.parse(File.read(TOKEN_FILE)) rescue nil
    @token = login if @token.nil?
  end

  def login
    if !ENV['USERNAME'] || !ENV['PASSWORD']
      abort "cannot login without credentials"
    end
    auth_request = {
      'username'      => ENV['USERNAME'],
      'password'      => ENV['PASSWORD'],
      'grant_type'    => 'password',
      'client_id'     => SENSE_CLIENT_ID,
      'client_secret' => SENSE_CLIENT_SECRET,
    }
    auth_response = @conn.post '/v1/oauth2/token', auth_request

    if auth_response.status != 200
      warn 'Authentication failed'
      return false
    end

    token = auth_response.body
    token['created_at'] = Time.now

    File.write(TOKEN_FILE, token.to_json)
    return token
  end

  # throws 400 if hours > 12
  def all_sensors(hours = 2)
    start = (Time.now - (hours * 60 * 60)).to_f * 1000
    response = @conn.get '/v1/room/all_sensors/hours', {'quantity' => hours, 'from_utc' => start.to_i}
    raise 'error' unless response.status == 200
    response.body
  end

  def current(unit = 'c')
    response = @conn.get '/v1/room/current', {'temp_unit' => unit}
    raise 'error' unless response.status == 200
    response.body
  end
end


sense = Sense.new
influxdb = InfluxDB::Client.new 'sense', time_precision: 'ms'

sense.current.each do |k,v|
  influxdb.write_point k, {values: { value: v["value"] }}
end

