require 'sinatra'
require 'nokogiri'
require 'haml'
require 'rest_client'
require 'crack'
require 'rack-flash'
use Rack::Flash
enable :sessions

configure do
  #setup MySQL connection:  
  #@config = YAML::load( File.open( 'config/settings.yml' ) )
  #@connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  #DataMapper.setup(:default, @connection)
  #DataMapper.finalize
  set :haml, {:format => :html5}
  set :spotify_playlist_id_constant, 'spotify:user:s%c3%a4ders%c3%a4rla:playlist:5Y55eeChjOVhzi58P0o0NZ'
end

helpers do
  
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
    file = RestClient.get host_url, {:params => {:uri => spotify_id}}        
    json = Crack::JSON.parse(file)
    return json
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
  @tracks = Hash.new
  @result = show_playlist(settings.spotify_playlist_id_constant)
  i = 0
  @result['tracks'].each do |doc|
    result = lookup_track(doc)
    @tracks[i] = result
    i = i + 1
  end
  haml :index
end

get '/search' do
  @result = search_spotify(params[:q])
  if @result.length == 0
    flash[:error] = "No results"
    redirect '/'
  else
    haml :search
  end
end

post '/remove/:index' do
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
end

post '/add/:id' do 
  track_id = [ params[:id].to_s ]
  if track_id
    count = playlist_count(settings.spotify_playlist_id_constant)
    result = add_to_playlist(track_id,settings.spotify_playlist_id_constant,count)
    if result.code == 200
      flash[:notice] = "Track has been added"
    else
      flash[:error] = "Could not add the track, try again"
    end
  end
  redirect "/"
end