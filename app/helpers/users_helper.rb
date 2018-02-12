module UsersHelper
  def user_object(username)
    content_tag :div, id: 'user-' + username, class: 'user_object' do
      link_to username, show_user_path(username)
    end
  end
end
