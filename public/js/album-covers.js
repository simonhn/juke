AlbumCover = function(api,elem) {
    this.api = api;
    this.elem = elem;
};
AlbumCover.prototype = {
    
    display: function(cover)
    {
       console.log(cover.image);
       //console.log(this.elem);
       
       $(this.elem).attr("src", cover.image);
       //$('<img src="'+cover.image+'">').hide().appendTo(this.elem).fadeIn();;
    },
    
    fetchCovers: function(artist, track)
    {
      this.api.getTrackInfo(
          artist,
          track,
          jQuery.proxy(this.handleResponse, this), 
          function(error) { console && console.log(error); }
      );
    },
    
    handleResponse: function(response)
    {
        if (response) {
            return this.display({
                image: response.track.album.image[0]['#text']
            });
        }
    }
};