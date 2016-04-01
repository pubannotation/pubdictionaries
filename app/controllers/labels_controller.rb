class LabelsController < ApplicationController
  def index
    @labels_grid = initialize_grid(Label)

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  def show
  end
end
