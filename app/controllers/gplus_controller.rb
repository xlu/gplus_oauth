require 'google/api_client'
require 'httpadapter/adapters/net_http'
require 'pp'
require 'yaml'

use Rack::Session::Pool, :expire_after => 86400 # 1 day

class GplusController < ApplicationController

  class TokenPair
    @refresh_token
    @access_token
    @expires_in
    @issued_at

    def update_token!(object)
      @refresh_token = object.refresh_token
      @access_token = object.access_token
      @expires_in = object.expires_in
      @issued_at = object.issued_at
    end

    def to_hash
      return {
        :refresh_token => @refresh_token,
        :access_token => @access_token,
        :expires_in => @expires_in,
        :issued_at => Time.at(@issued_at)
      }
    end
  end

  def login
    @client = get_client()
    if session[:token]
      puts "session[:token]=#{session[:token]}"
      # Load the access token here if it's available
      @client.authorization.update_token!(session[:token].to_hash)
    end

    @plus = @client.discovered_api('plus', 'v1')
    puts "token=#{@client.authorization.access_token}"
    puts "request.path_info=#{request.path_info}"

    @login_url = @client.authorization.authorization_uri.to_s  #TODO user revisits login page without logout
  end

  def import
    #http://localhost:3000/import?code=4/Afm3oTPtuOtWFXbOdSnGS290fKq5
    @client = get_client(params[:code])
    @client.authorization.fetch_access_token!

    if session[:token]
      # Load the access token here if it's available
      @client.authorization.update_token!(session[:token].to_hash)
    else
      token_pair = TokenPair.new
      token_pair.update_token!(@client.authorization)
      # Persist the token here
      session[:token] = token_pair.to_hash
      p token_pair
    end

    @plus = @client.discovered_api('plus', 'v1')

    # Fetch a known public activity
    status = fetch_one_public_activity(@client, @plus, 'z12ydv2rbtv4drryr04cj1u4hsa3gdwy1h4')
    @public_activity = JSON.parse(status.body)

    # Fetch my profile
    status = fetch_my_profile(@client, @plus)
    @profile = JSON.parse(status.body)

    # Fetch my activities
    status = fetch_my_public_activity(@client, @plus)
    @activities = JSON.parse(status.body)
  end

  def list

  end

  # Clears the token saved in the session
  def clear_session
    session.delete(:token)
    redirect to('/')
  end

private

  def fetch_one_public_activity(client, gplus, activity_id)
    # Fetch a known public activity
    status = client.execute(
      gplus.activities.get,
      'activityId' => activity_id
    )
    return status
  end

  def fetch_my_profile(client, gplus)
    status = client.execute(
      gplus.people.get,
      'userId' => 'me'
    )
    return status
  end

  def fetch_my_public_activity(client, gplus)
    status = client.execute(
      gplus.activities.list,
      'userId' => 'me', 'collection' => 'public'
    )
    return status
  end

  def read_oauth_config
    gplus_config_filename = File.join(Rails.root, "config", "gplus.yml")
    raise "#{ga_config_filename} does not exist." unless File.exists?(gplus_config_filename)
    yaml = File.open(gplus_config_filename) {|yf| YAML::load(yf) }
    env = Rails.env
    oauth_scopes = yaml[env]["oauth_scopes"]
    oauth_client_id = yaml[env]["oauth_client_id"]
    oauth_client_secret = yaml[env]["oauth_client_secret"]
    google_api_key = yaml[env]["google_api_key"]
    return oauth_scopes, oauth_client_id, oauth_client_secret, google_api_key
  end

  def get_client(code = nil)
    oauth_scopes, oauth_client_id, oauth_client_secret, google_api_key = read_oauth_config
    set :oauth_scopes, oauth_scopes
    set :oauth_client_id, oauth_client_id
    set :oauth_client_secret, oauth_client_secret
    set :google_api_key, google_api_key

    client = Google::APIClient.new(
      :authorization => :oauth_2,
      :host => 'www.googleapis.com',
      :http_adapter => HTTPAdapter::NetHTTPAdapter.new
    )

    client.authorization.client_id = settings.oauth_client_id
    client.authorization.client_secret = settings.oauth_client_secret
    client.authorization.scope = settings.oauth_scopes
    client.authorization.redirect_uri = "http://#{request.host_with_port}/import"  #match gplus callback url
    client.authorization.code = code if code
    return client
  end

end
