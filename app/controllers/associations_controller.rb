class AssociationsController < ApplicationController
  # GET /associations
  # GET /associations.json
  def index
    @associations = Association.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @associations }
    end
  end

  # GET /associations/1
  # GET /associations/1.json
  def show
    @association = Association.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @association }
    end
  end

  # GET /associations/new
  # GET /associations/new.json
  def new
    @association = Association.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @association }
    end
  end

  # GET /associations/1/edit
  def edit
    @association = Association.find(params[:id])
  end

  # POST /associations
  # POST /associations.json
  def create
    @association = Association.new(params[:association])

    respond_to do |format|
      if @association.save
        format.html { redirect_to @association, notice: 'Association was successfully created.' }
        format.json { render json: @association, status: :created, location: @association }
      else
        format.html { render action: "new" }
        format.json { render json: @association.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /associations/1
  # PUT /associations/1.json
  def update
    @association = Association.find(params[:id])

    respond_to do |format|
      if @association.update_attributes(params[:association])
        format.html { redirect_to @association, notice: 'Association was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @association.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /associations/1
  # DELETE /associations/1.json
  def destroy
    @association = Association.find(params[:id])
    @association.destroy

    respond_to do |format|
      format.html { redirect_to associations_url }
      format.json { head :no_content }
    end
  end
end
