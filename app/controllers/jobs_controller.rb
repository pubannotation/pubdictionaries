class JobsController < ApplicationController
  # Require authentication for all actions except :index, :show, and some others.
  before_action :authenticate_user!, except: [:show]

  def index
    raise 'Not authorized.' unless current_user.admin
    @jobs_grid = initialize_grid(Job)
  end

  # GET /jobs/1
  # GET /jobs/1.json
  def show
    @job = Job.find(params[:id])

    respond_to do |format|
      format.any  { render json: @job.description(request.host_with_port), content_type: 'applicatin/json' }
      format.csv  { send_data @job.description_csv(request.host_with_port), type: :csv }
      format.tsv  { send_data @job.description_csv(request.host_with_port), type: :csv }
      format.json { render json: @job.description(request.host_with_port), type: :json }
    end
  end

  # DELETE /jobs/1
  # DELETE /jobs/1.json
  def destroy
    job = Job.find(params[:id])
    job.destroy_if_not_running

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path }
      format.json { head :no_content }
    end
  end

  # DELETE /jobs
  def destroy_all
    jobs = Job.all
    jobs.each{|job| job.destroy_if_not_running}

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path }
      format.json { head :no_content }
    end
  end

end
