class JobsController < ApplicationController
  # GET /jobs/1
  # GET /jobs/1.json
  def show
    @job = Job.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @job }
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
end
