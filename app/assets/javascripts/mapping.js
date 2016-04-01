var toggleDictionary = function(e){
  var isSearched = e.parent().attr('id') == 'search_target_dictionaries';
  $(e).remove();
  if (isSearched){
    $(e).children('i').removeClass('fa-times-circle');
    $(e).children('i').addClass('fa-plus-circle');
    $('#dialog').append(e);
  }else{
    $(e).children('i').addClass('fa-times-circle');
    $(e).children('i').removeClass('fa-plus-circle');
    $('#search_dictionaries').append(e);
  }
};
