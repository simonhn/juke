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
  
  @config = YAML::load( File.open( 'config/settings.yml' ) )
  @connection = "#{@config['adapter']}://#{@config['username']}:#{@config['password']}@#{@config['host']}/#{@config['database']}";
  #DataMapper.setup(:default, @connection)
  #DataMapper.finalize
  set :haml, {:format => :html5}
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
    
    def add_to_playlist(track,spotify_playlist_id)
      url = "http://localhost:1337/playlist/"+spotify_playlist_id+"/add?index=0"
      uri = URI.escape(url)
      result = RestClient.post uri, track.inspect
      return result
    end
    
    def show_playlist(spotify_playlist_id)
      url = "http://localhost:1337/playlist/"+spotify_playlist_id
      uri = URI.escape(url)
      file = RestClient.get uri
      json = Crack::JSON.parse(file)
      return json
    end
    
    def lookup_track(spotify_id)
      host_url = 'http://ws.spotify.com/lookup/1/.json'
      file = RestClient.get host_url, {:params => {:uri => spotify_id}}        
      json = Crack::JSON.parse(file)
      return json
    end
end

get '/' do
  @tracks = Hash.new
  @result = show_playlist('spotify:user:s%c3%a4ders%c3%a4rla:playlist:5Y55eeChjOVhzi58P0o0NZ')
  @result['tracks'].each do |doc|
    result = lookup_track(doc)
    @tracks[result['track']['name']] = result['track']['artists'].first['name']
  end
  haml :index
end

post '/search' do
  @result = search_spotify(params[:q])
  haml :search
end

get '/add' do 
  track_string = [ params[:track].to_s ]
  result = add_to_playlist(track_string,'spotify:user:s%c3%a4ders%c3%a4rla:playlist:5Y55eeChjOVhzi58P0o0NZ')
  if result.code == 200
    flash[:notice] = "Your track has been added"
  else
    flash[:error] = "We could not add the track, try again"
  end
  redirect "/"
end