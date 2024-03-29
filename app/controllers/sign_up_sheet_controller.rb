class SignUpSheetController < ApplicationController
  require 'rgl/adjacency'
  require 'rgl/dot'
  require 'graph/graphviz_dot'
  require 'rgl/topsort'
  include DeadlineHelper
  include ManageTeamHelper

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [:destroy, :create, :update],
         :redirect_to => {:action => :list}

  def add_signup_topics_staggered
    load_add_signup_topics(params[:id])

    @review_rounds = Assignment.find(params[:id]).get_review_rounds
    @topics = SignUpTopic.find_all_by_assignment_id(params[:id])

    #Use this until you figure out how to initialize this array
    @duedates = SignUpTopic.find_by_sql("SELECT s.id as topic_id FROM sign_up_topics s WHERE s.assignment_id = " + params[:id].to_s)

    if !@topics.nil?
      i=0
      @topics.each { |topic|

        @duedates[i]['t_id'] = topic.id
        @duedates[i]['topic_identifier'] = topic.topic_identifier
        @duedates[i]['topic_name'] = topic.topic_name

        for j in 1..@review_rounds

          if j == 1
            duedate_subm = find_by_topic(topic,'submission')
            #TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('submission').id)
            duedate_rev =  find_by_topic(topic,'review')
            #TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('review').id)
          else
            duedate_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(topic.id, DeadlineType.find_by_name('resubmission').id, j)
            duedate_rev = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(topic.id, DeadlineType.find_by_name('rereview').id, j)
          end
          if !duedate_subm.nil? && !duedate_rev.nil?
            @duedates[i]['submission_'+ j.to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
            @duedates[i]['review_'+ j.to_s] = DateTime.parse(duedate_rev['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
          else
            #the topic is new. so copy deadlines from assignment
            set_of_due_dates = DueDate.find_all_by_assignment_id(params[:id])
            set_of_due_dates.each { |due_date|
              create_topic_deadline(due_date, 0, topic.id)
            }
            # code execution would have hit the else part during review_round one. So we'll do only round one
            duedate_subm = find_by_topic(topic,'submission')
            #TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('submission').id)
            duedate_rev = find_by_topic(topic,'review')
            #TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('review').id)
            @duedates[i]['submission_'+ j.to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
            @duedates[i]['review_'+ j.to_s] = DateTime.parse(duedate_rev['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
          end

        end
        duedate_subm = find_by_topic(topic,'metareview')
        #TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name('metareview').id)
        if !duedate_subm.nil?
          @duedates[i]['submission_'+ (@review_rounds+1).to_s] = DateTime.parse(duedate_subm['due_at'].to_s).strftime("%Y-%m-%d %H:%M:%S")
        else
          @duedates[i]['submission_'+ (@review_rounds+1).to_s] = nil
        end
        i = i + 1
      }
    end
  end
  def find_by_topic(topic, status)
    TopicDeadline.find_by_topic_id_and_deadline_type_id(topic.id, DeadlineType.find_by_name(status).id)
  end
 def add_signup_topics
    load_add_signup_topics(params[:id])
  end

  def view_publishing_rights
    load_add_signup_topics(params[:id])
  end

  def load_add_signup_topics(assignment_id)
    @id = assignment_id
    @sign_up_topics = SignUpTopic.find(:all, :conditions => ['assignment_id = ?', assignment_id])
    @slots_filled = SignUpTopic.find_slots_filled(assignment_id)
    @slots_waitlisted = SignUpTopic.find_slots_waitlisted(assignment_id)

    @assignment = Assignment.find(assignment_id)
    if !@assignment.team_assignment
      @participants = SignedUpUser.find_participants(assignment_id)
    else
      @participants = SignedUpUser.find_team_participants(assignment_id)
    end
  end

  def new
    @id = params[:id]
    @sign_up_topic = SignUpTopic.new
  end

  #This method is used to create signup topics
  #In this code params[:id] is the assignment id and not topic id. The intuition is 
  #that assignment id will virtually be the signup sheet id as well as we have assumed 
  #that every assignment will have only one signup sheet
  def create
    topic = SignUpTopic.find_by_topic_name_and_assignment_id(params[:topic][:topic_name], params[:id])

    #if the topic already exists then update
    if topic != nil
      topic.topic_identifier = params[:topic][:topic_identifier]

      #While saving the max choosers you should be careful; if there are users who have signed up for this particular
      #topic and are on waitlist, then they have to be converted to confirmed topic based on the availability. But if
      #there are choosers already and if there is an attempt to decrease the max choosers, as of now I am not allowing
      #it.
      if SignedUpUser.find_by_topic_id(topic.id).nil? || topic.max_choosers == params[:topic][:max_choosers]
        topic.max_choosers = params[:topic][:max_choosers]
      else
        if topic.max_choosers.to_i < params[:topic][:max_choosers].to_i
          topic.update_waitlisted_users(params[:topic][:max_choosers])
          topic.max_choosers = params[:topic][:max_choosers]
        else
          flash[:error] = 'Value of maximum choosers can only be increased! No change has been made to max choosers.'
        end
      end

      topic.category = params[:topic][:category]
      #topic.assignment_id = params[:id] 
      topic.save
      redirect_to_sign_up(params[:id])
    else
      @sign_up_topic = SignUpTopic.new
      @sign_up_topic.topic_identifier = params[:topic][:topic_identifier]
      @sign_up_topic.topic_name = params[:topic][:topic_name]
      @sign_up_topic.max_choosers = params[:topic][:max_choosers]
      @sign_up_topic.category = params[:topic][:category]
      @sign_up_topic.assignment_id = params[:id]

      @assignment = Assignment.find(params[:id])

      if @assignment.staggered_deadline?
        topic_set = Array.new
        topic = @sign_up_topic.id

      end

      if @sign_up_topic.save
        #NotificationLimit.create(:topic_id => @sign_up_topic.id)
        flash[:notice] = 'Topic was successfully created.'
        redirect_to_sign_up(params[:id])
      else
        render :action => 'new', :id => params[:id]
      end
    end
  end

  def redirect_to_sign_up(assignment_id)
    assignment = Assignment.find(assignment_id)
    if assignment.staggered_deadline == true
      redirect_to :action => 'add_signup_topics_staggered', :id => assignment_id
    else
      redirect_to :action => 'add_signup_topics', :id => assignment_id
    end
  end

  #This method is used to delete signup topics
  def delete
    @topic = SignUpTopic.find(params[:id])

    if !@topic.nil?
      @topic.destroy
    else
      flash[:error] = "Topic could not be deleted"
    end

    #if this assignment has staggered deadlines then destroy the dependencies as well    
    if Assignment.find(params[:assignment_id])['staggered_deadline'] == true
      dependencies = TopicDependency.find_all_by_topic_id(params[:id])
      if !dependencies.nil?
        dependencies.each { |dependency| dependency.destroy }
      end
    end
    redirect_to_sign_up(params[:assignment_id])
  end

  def edit
    @topic = SignUpTopic.find(params[:id])
    @assignment_id = params[:assignment_id]
  end

  def update
    topic = SignUpTopic.find(params[:id])

    if !topic.nil?
      topic.topic_identifier = params[:topic][:topic_identifier]

      #While saving the max choosers you should be careful; if there are users who have signed up for this particular
      #topic and are on waitlist, then they have to be converted to confirmed topic based on the availability. But if
      #there are choosers already and if there is an attempt to decrease the max choosers, as of now I am not allowing
      #it.
      if SignedUpUser.find_by_topic_id(topic.id).nil? || topic.max_choosers == params[:topic][:max_choosers]
        topic.max_choosers = params[:topic][:max_choosers]
      else
        if topic.max_choosers.to_i < params[:topic][:max_choosers].to_i
          topic.update_waitlisted_users(params[:topic][:max_choosers])
          topic.max_choosers = params[:topic][:max_choosers]
        else
          flash[:error] = 'Value of maximum choosers can only be increased! No change has been made to max choosers.'
        end
      end

      topic.category = params[:topic][:category]
      topic.topic_name = params[:topic][:topic_name]
      topic.save
    else
      flash[:error] = "Topic could not be updated"
    end
    redirect_to_sign_up(params[:assignment_id])
  end
  def save_topic_dependencies
    # Prevent injection attacks - we're using this in a system() call later
    params[:assignment_id] = params[:assignment_id].to_i.to_s

    topics = SignUpTopic.find_all_by_assignment_id(params[:assignment_id])
    topics = topics.collect { |topic|
      #if there is no dependency for a topic then there wont be a post for that tag.
      #if this happens store the dependency as "0"
      if !params['topic_dependencies_' + topic.id.to_s].nil?
        [topic.id, params['topic_dependencies_' + topic.id.to_s][:dependent_on]]
      else
        [topic.id, ["0"]]
      end
    }


    # Save the dependency in the topic dependency table
    TopicDependency.save_dependency(topics)

    node = 'id'
    dg = build_dependency_graph(topics, node)

    if dg.acyclic?
      #This method produces sets of vertexes which should have common start time/deadlines
      set_of_topics = create_common_start_time_topics(dg)
      set_start_due_date(params[:assignment_id], set_of_topics)
      @top_sort = dg.topsort_iterator.to_a
    else
      flash[:error] = "There may be one or more cycles in the dependencies. Please correct them"
    end


    node = 'topic_name'
    dg = build_dependency_graph(topics, node) # rebuild with new node name

    graph_output_path = 'public/images/staggered_deadline_assignment_graph'
    FileUtils::mkdir_p graph_output_path
    dg.write_to_graphic_file('jpg', "#{graph_output_path}/graph_#{params[:assignment_id]}")

    redirect_to_sign_up(params[:assignment_id])
  end

  #If the instructor needs to explicitly change the start/due dates of the topics
  def save_topic_deadlines

    due_dates = params[:due_date]

    review_rounds = Assignment.find(params[:assignment_id]).get_review_rounds
    due_dates.each { |due_date|
      for i in 1..review_rounds
        if i == 1
          topic_deadline_type_subm = DeadlineType.find_by_name('submission').id
          topic_deadline_type_rev = DeadlineType.find_by_name('review').id
        else
          topic_deadline_type_subm = DeadlineType.find_by_name('resubmission').id
          topic_deadline_type_rev = DeadlineType.find_by_name('rereview').id
        end

        topic_deadline_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(due_date['t_id'].to_i, topic_deadline_type_subm, i)
        topic_deadline_subm.update_attributes({'due_at' => due_date['submission_' + i.to_s]})
        flash[:error] = "Please enter a valid " + (i > 1 ? "Resubmission deadline " + (i-1).to_s : "Submission deadline") if topic_deadline_subm.errors.length > 0

        topic_deadline_rev = TopicDeadline.find_by_topic_id_and_deadline_type_id_and_round(due_date['t_id'].to_i, topic_deadline_type_rev, i)
        topic_deadline_rev.update_attributes({'due_at' => due_date['review_' + i.to_s]})
        flash[:error] = "Please enter a valid Review deadline " + (i > 1 ? (i-1).to_s : "") if topic_deadline_rev.errors.length > 0
      end

      topic_deadline_subm = TopicDeadline.find_by_topic_id_and_deadline_type_id(due_date['t_id'], DeadlineType.find_by_name('metareview').id)
      topic_deadline_subm.update_attributes({'due_at' => due_date['submission_' + (review_rounds+1).to_s]})
      flash[:error] = "Please enter a valid Meta review deadline" if topic_deadline_subm.errors.length > 0
    }

    redirect_to_sign_up(params[:assignment_id])
  end


  def build_dependency_graph(topics, node)
    dg = RGL::DirectedAdjacencyGraph.new

    #create a graph of the assignment with appropriate dependency
    topics.collect { |topic|
      topic[1].each { |dependent_node|
        edge = Array.new
        #if a topic is not dependent on any other topic
        dependent_node = dependent_node.to_i
        if dependent_node == 0
          edge.push("fake")
        else
          #if we want the topic names to be displayed in the graph replace node to topic_name
          edge.push(SignUpTopic.find(dependent_node)[node])
        end
        edge.push(SignUpTopic.find(topic[0])[node])
        dg.add_edges(edge)
      }
    }
    #remove the fake vertex
    dg.remove_vertex("fake")
    dg
  end

  def create_common_start_time_topics(dg)
    dg_reverse = dg.clone.reverse()
    set_of_topics = Array.new

    while !dg_reverse.empty?
      i = 0
      temp_vertex_array = Array.new
      dg_reverse.each_vertex { |vertex|
        if dg_reverse.out_degree(vertex) == 0
          temp_vertex_array.push(vertex)
        end
      }
      #this cannot go inside the if statement above
      temp_vertex_array.each { |vertex|
        dg_reverse.remove_vertex(vertex)
      }
      set_of_topics.insert(i, temp_vertex_array)
      i = i + 1
    end
    set_of_topics
  end






end
