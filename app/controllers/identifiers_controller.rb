class IdentifiersController < ApplicationController
  def index
    @identifiers_grid = initialize_grid(Identifier)

    respond_to do |format|
      format.html
    end
  end

  def show
  end
end
