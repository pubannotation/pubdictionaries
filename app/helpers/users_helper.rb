module UsersHelper
	def user_object(username, role = nil, control_p = false)
		link_html = link_to(username, show_user_path(username))
		link_html += ' '
		link_html += link_to('<i class="fa fa-minus-square" aria-hidden="true"></i>'.html_safe, manager_dictionary_path(@dictionary, username), method: :delete, title: 'Remove').html_safe if control_p

		if role.present?
			content_tag :div, id: 'user-' + username, class: "user_object #{role}", title: role do
				link_html
			end
		else
			content_tag :div, id: 'user-' + username, class: "user_object" do
				link_html
			end
		end
	end

	def login_with_google
<<HEREDOC
<div style="display:inline-block; color:#fff">
  <div style="display:inline-block; margin: 0; padding:5px; background-color:#99f"><i class="fa fa-google" style="width:16px; height:15px"></i></div><div style="display:inline-block; margin:0; padding:5px; background-color:#88f"> Log in with Google</div>
</div>
HEREDOC
  end
end
