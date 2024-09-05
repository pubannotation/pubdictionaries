class Api::V1::JobsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def destroy
    job = Job.find(params[:id])

    if job.running?
      render json: { message: "Job #{params[:id]} is currently running and cannot be deleted." }, status: :unprocessable_entity
      return
    end

    job.destroy_if_not_running
    render json: { message: "Job #{params[:id]} was successfully deleted." }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end
end
