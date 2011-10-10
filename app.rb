require 'sinatra'
require 'nokogiri'
require 'haml'
require 'rest_client'
require 'crack'
require 'rack-flash'
require 'oa-oauth'
require 'dm-core'
require 'dm-sqlite-adapter'
require 'dm-migrations'

use Rack::Flash
enable :sessions

class User
  include DataMapper::Resource
  property :id,           Serial
  property :uid,          String
  property :name,         String
  property :nickname,     String
  property :image,        String
  property :created_at,   DateTime
  has n, :tracks, :through => Resource
  
end

class Track
  include DataMapper::Resource
  property :spotify_id,     String, :key => true
  property :artist_title,   String
  property :track_title,    String
  property :created_at,     DateTime
  has n, :users, :through => Resource  
end

configure do
  
  #setup db connection:  
  DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/database.db")
  DataMapper.finalize
  #DataMapper.auto_upgrade!
  #DataMapper.auto_migrate!
  @config = YAML::load( File.open( 'config/settings.yml' ) )
  twitter_key = "#{@config['CONSUMER_KEY']}"
  twitter_secret = "#{@config['CONSUMER_SECRET']}"
  facebook_key = "#{@config['App_ID']}"
  facebook_secret = "#{@config['App_Secret']}"
  
  use OmniAuth::Builder do
    provider :facebook,  facebook_key, facebook_secret
    provider :twitter, twitter_key, twitter_secret
  end

  set :haml, {:format => :html5}
  set :spotify_playlist_id_constant, 'spotify:user:s%c3%a4ders%c3%a4rla:playlist:5Y55eeChjOVhzi58P0o0NZ'
end

helpers do
  
  def current_user
    @current_user ||= User.get(session[:user_id]) if session[:user_id]
  end
  
  def protected!
      unless authorized?
        response['WWW-Authenticate'] = %(Basic realm="Auth needed for post requests")
        throw(:halt, [401, "Not authorized\n"])
      end
    end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @user =  ENV['MY_SITE_USERNAME']
    @pass = ENV['MY_SITE_SECRET']
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [@user.to_s, @pass.to_s]
  end
      
  def search_spotify(q)
    result = Hash.new
    host_url = 'http://ws.spotify.com/search/1/track.json'
    file = RestClient.get host_url, {:params => {:q => q}}        
    json = Crack::JSON.parse(file)
    json['tracks'].each do |j|
      territories = j['album']['availability']['territories']
      in_sweden = territories.include? 'SE'
      worldwide = territories.include? 'worldwide'
      spotify_uri = j['href']
  	  if (in_sweden or worldwide) and !spotify_uri.empty?
  	    result[spotify_uri] = j
      end
    end
    
    return result
  end
    
  def add_to_playlist(track,spotify_playlist_id,count=0)
    url = "http://127.0.0.1:1337/playlist/#{spotify_playlist_id}/add?index=#{count.to_s}"
    uri = URI.escape(url)
    result = RestClient.post uri, track.inspect
    return result
  end
  
  def show_playlist(spotify_playlist_id)
    url = "http://127.0.0.1:1337/playlist/"+spotify_playlist_id
    uri = URI.escape(url)
    file = RestClient.get uri
    json = Crack::JSON.parse(file)
    return json
  end
  
  def playlist_count(spotify_playlist_id)
    url = "http://127.0.0.1:1337/playlist/"+spotify_playlist_id
    uri = URI.escape(url)
    file = RestClient.get uri
    json = Crack::JSON.parse(file)
    return json['tracks'].length
  end
      
  def lookup_track(spotify_id)
    host_url = 'http://ws.spotify.com/lookup/1/.json'
    #response = HTTParty.get(host_url)
    #puts response.body, response.code, response.message, response.headers.inspect
    
    file = RestClient.get host_url, {:params => {:uri => spotify_id}}
    json = Crack::JSON.parse(file)
    return json
  end
  
  def get_track(spotify_id)
    #do we have it in the db?
    db_result = Track.first(:spotify_id => spotify_id)
   
    #yes we do
    if db_result
      return db_result
    #no we dont
    else  
      #lookup in spotify metadata api
      spotify_result = lookup_track(spotify_id)
      #save result for future
      track = Track.create(
        :spotify_id => spotify_id, 
        :artist_title => spotify_result['track']['artists'].first['name'].to_s, 
        :track_title => spotify_result['track']['name'].to_s,
        :created_at => Time.now
        )
      track.save      
      return track
    end
  end
  
  def delete_track(spotify_playlist_id, index)
    url = URI.escape("http://127.0.0.1:1337/playlist/#{spotify_playlist_id}/remove?index=#{index.to_s}&count=1")
    result = RestClient.post url, :foo => 'bar'
    return result
  end
end

not_found do
  haml :'404'
end

error do
  haml :'500'
end

get '/' do
  @bruger = current_user
  @session = session[:user_id].to_s
  
  @tracks = Hash.new
  @result = show_playlist(settings.spotify_playlist_id_constant)
  i = 0
  @result['tracks'].each do |doc|
    result = get_track(doc)
    @tracks[i] = result
    i = i + 1
  end
  haml :index
end

get '/db' do
  @users = User.all
  @tracks = Track.all
  haml :db
end

get '/auth/:name/callback' do
  auth = request.env["omniauth.auth"]
  user = User.first_or_create({ :uid => auth["uid"]}, { 
    :uid => auth["uid"], 
    :nickname => auth["user_info"]["nickname"], 
    :name => auth["user_info"]["name"],
    :image => auth["user_info"]["image"], 
    :created_at => Time.now })
  session[:user_id] = user.id
  flash[:info] = "You are now logged in"
  redirect request.env["omniauth.origin"]  || '/'
end

get '/auth/failure' do
  'Hmmm...login issues ey? Did you provide the correct credentials?'
end

get '/sign_in/:provider/?' do
  if params[:provider]=='twitter'
    redirect '/auth/twitter'
  elsif params[:provider]=='facebook'
    redirect '/auth/facebook'
  end
end

# either /log_out, /logout, /sign_out, or /signout will end the session and log the user out
["/sign_out/?", "/signout/?", "/log_out/?", "/logout/?"].each do |path|
  get path do
    session[:user_id] = nil
    flash[:info] = "You are now logged out"
    redirect back
  end
end

get '/search' do
  @result = search_spotify(params[:q])
  if @result.length == 0
    flash[:error] = "No results"
    redirect back
  else
    haml :search
  end
end

post '/remove/:index' do
  if current_user
    index = params[:index]
    if index
      result = delete_track(settings.spotify_playlist_id_constant, index)
      if result.code == 200
        flash[:notice] = "Track has been removed"
      else
        flash[:error] = "Could not remove the track, try again"
      end
    end
    redirect '/'
  else
    flash[:error] = "Only logged in users can remove tracks."
    redirect back
  end
end

post '/add/:id' do
  if current_user
    track_id = [ params[:id].to_s ]
    if track_id
      count = playlist_count(settings.spotify_playlist_id_constant)
      result = add_to_playlist(track_id,settings.spotify_playlist_id_constant,count)
      if result.code == 200
        #add to TrackUser table:
        track = get_track(params[:id].to_s)
        cu = current_user
        user_track = cu.tracks << track
        user_track.save        
        flash[:notice] = "Track has been added"
      else        
        flash[:error] = "Could not add the track, try again"
      end
    end
    redirect "/"
  else
    flash[:error] = "Only logged in users can add tracks."
    redirect back
  end
end