NowPlaying = function(api, user, interval) {
    this.api = api;
    this.user = user;
    
    /* AutoUpdate frequency - Last.fm API rate limits at 1/sec */
    this.interval = interval || 5;
};
NowPlaying.prototype = {
    
    display: function(track)
    {
      //only redraw if the track is new 
       if ( ($('#artist').text() !== track.artist) && ($('#track').text()!==track.name) )
       {          
          $('#playing').fadeOut("normal", function() {
                  $(this).remove();
          });
          $('.now').removeClass("now");
          $('#artist').text(track.artist).hide().fadeIn();
          $('.separator').text(" - ").hide().fadeIn();
          $('#track').text(track.name).hide().fadeIn();
          //$('div.track:contains('+track.name+')').append('<span id="playing"><img alt="Now Playing" id="del-icon" src="/images/speaker.svg"></span>').hide().fadeIn();
           $('<span id="playing"><span><img alt="Now Playing" id="del-icon" src="/images/speaker-grey.svg"></span></span>').hide().appendTo('div.track:contains('+track.name+')').fadeIn();
          $('div.track:contains('+track.name+')').addClass('now');
        }
    },
    
    update: function()
    {
        this.api.getNowPlayingTrack(
            this.user,
            jQuery.proxy(this.handleResponse, this), 
            function(error) { console && console.log(error); }
        );
    },
    
    autoUpdate: function()
    {
        // Do an immediate update, don't wait an interval period
        this.update();
        
        // Try and avoid repainting the screen when the track hasn't changed
        setInterval(jQuery.proxy(this.update, this), this.interval * 1000);
    },
    
    handleResponse: function(response)
    {
        if (response) {
            this.display({
                // The API response can vary depending on the user, so be defensive
                artist: response.artist['#text'] || response.artist.name,
                name: response.name,
                image: response.image[0]['#text']
            });
        }
        else {
            this.display({artist: ' ', name: ''});
        }
    }
};