class UserDictionariesController < ApplicationController
  # GET /user_dictionaries
  # GET /user_dictionaries.json
  def index
    @user_dictionaries = UserDictionary.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @user_dictionaries }
    end
  end

  # GET /user_dictionaries/1
  # GET /user_dictionaries/1.json
  def show
    @user_dictionary = UserDictionary.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @user_dictionary }
    end
  end

  # GET /user_dictionaries/new
  # GET /user_dictionaries/new.json
  def new
    @user_dictionary = UserDictionary.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @user_dictionary }
    end
  end

  # GET /user_dictionaries/1/edit
  def edit
    @user_dictionary = UserDictionary.find(params[:id])
  end

  # POST /user_dictionaries
  # POST /user_dictionaries.json
  def create
    @user_dictionary = UserDictionary.new(params[:user_dictionary])

    respond_to do |format|
      if @user_dictionary.save
        format.html { redirect_to @user_dictionary, notice: 'User dictionary was successfully created.' }
        format.json { render json: @user_dictionary, status: :created, location: @user_dictionary }
      else
        format.html { render action: "new" }
        format.json { render json: @user_dictionary.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /user_dictionaries/1
  # PUT /user_dictionaries/1.json
  def update
    @user_dictionary = UserDictionary.find(params[:id])

    respond_to do |format|
      if @user_dictionary.update_attributes(params[:user_dictionary])
        format.html { redirect_to @user_dictionary, notice: 'User dictionary was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @user_dictionary.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_dictionaries/1
  # DELETE /user_dictionaries/1.json
  def destroy
    @user_dictionary = UserDictionary.find(params[:id])
    @user_dictionary.destroy

    respond_to do |format|
      format.html { redirect_to user_dictionaries_url }
      format.json { head :no_content }
    end
  end
end
