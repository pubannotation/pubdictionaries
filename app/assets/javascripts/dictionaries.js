
// Excerpted from the Web.
$(function() {
    //  jQueryUI 1.10 and HTML5 ready
    //      http://jqueryui.com/upgrade-guide/1.10/#removed-cookie-option 
    //  Documentation
    //      http://api.jqueryui.com/tabs/#option-active
    //      http://api.jqueryui.com/tabs/#event-activate
    //      http://balaarjunan.wordpress.com/2010/11/10/html5-session-storage-key-things-to-consider/
    //
    //  Define friendly index name
    var index = 'key';
    //  Define friendly data store name
    var dataStore = window.sessionStorage;
    //  Start magic!
    try {
        // getter: Fetch previous value
        var oldIndex = dataStore.getItem(index);
    } catch(e) {
        // getter: Always default to first tab in error state
        var oldIndex = 0;
    }
    $('#tabs').tabs({
        // The zero-based index of the panel that is active (open)
        active : oldIndex,
        // Triggered after a tab has been activated
        activate : function( event, ui ){
            //  Get future value
            var newIndex = ui.newTab.parent().children().index(ui.newTab);
            //  Set future value
            dataStore.setItem( index, newIndex ) 
        }
    }); 
}); 

$(window).bind("load", function() {
    $("div.slide_show_inner_div").slideViewerPro({
        typo: true,

        galBorderWidth: 2,
        galBorderColor: "#8888ff",
        
        thumbsTopMargin: 10,
        thumbsRightMargin: 10,
        thumbsBorderWidth: 3,
        thumbsBorderOpacity: 0,
        thumbsActiveBorderColor: "#aaaa22",
        thumbsActiveBorderOpacity: 0.8,

        buttonsTextColor: "#0000ff",
        leftButtonInner: "&#8656;",
        rightButtonInner: "&#8658;",
    });
});

$(document).ready(function() {
    var clip = new ZeroClipboard($("#d_clip_button"))
});
