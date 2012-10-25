module ManageTeamHelper
  def create_team(assignment_id)
    assignment = Assignment.find(assignment_id)
    #check_for_existing_team_name(parent,generate_team_name(parent.name))
    teamname = generate_team_name(assignment.name)
    team = AssignmentTeam.create(:name => teamname, :parent_id => assignment.id)
    TeamNode.create(:parent_id => assignment.id, :node_object_id => team.id)
    team
  end

  def generate_team_name(teamnameprefix)
    counter = 1
    while (true)
      teamname = teamnameprefix + "_Team#{counter}"
      if (!Team.find_by_name(teamname))
        return teamname
      end
      counter=counter+1
    end
  end

    def create_team_users(user, team_id)
    #user = User.find_by_name(params[:user][:name].strip)
    if !user
      urlCreate = url_for :controller => 'users', :action => 'new'
      flash[:error] = "\"#{params[:user][:name].strip}\" is not defined. Please <a href=\"#{urlCreate}\">create</a> this user before continuing."
    end
    team = Team.find(team_id)
    team.add_member(user)
    end

  def get_team_details(assignment_id, topic_id)

    query = "select t.name, t.comments_for_advertisement, p.handle,t.id as team_id, p.id as participant_id, p.topic_id as topic_id, p.parent_id as assignment_id"
    query = query + " from teams t, teams_users tu, participants p"
    query = query + " where"
    query = query + " p.parent_id = '#{assignment_id}' and"
    query = query + " p.topic_id = '#{topic_id}' and"
    query = query + " t.parent_id = p.parent_id and"
    query = query + " tu.user_id = p.user_id and"
    query = query + " t.id = tu.team_id"
    query = query + " group by t.name;"

    SignUpTopic.find_by_sql(query)

  end
  def team_details
    if !(assignment = Assignment.find(params[:assignment_id])).nil? and !(topic = SignUpTopic.find(params[:id])).nil?
      @results =get_team_details(assignment.id, topic.id)
      @results.each do |result|
        result.attributes().each do |attr|
          if attr[0].equal? "name"
            @current_team_name = attr[1]
          end
        end
      end
      @results.each { |result|
        @team_members = ""
        TeamsUser.find_all_by_team_id(result[:team_id]).each { |teamuser|
          puts 'Userblaahsdb asd' +User.find(teamuser.user_id).to_json
          @team_members+=User.find(teamuser.user_id).name+" "
        }
      }
      #@team_members = find_team_members(topic)
    end
  end
end
