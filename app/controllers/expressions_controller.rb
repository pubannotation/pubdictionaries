class ExpressionsController < ApplicationController
  include ExpressionsHelper

  def search
    if params[:terms].present?
      if params[:dictionaries].present?
        # when filtered by dictionaries
        @dictionaries = Dictionary.where(['title IN (?)', params[:dictionaries]])
        if @dictionaries.present?
          dictionary_ids = @dictionaries.collect{|dictionary| dictionary.id }
          expressions = Expression.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.dictionaries(dictionary_ids).includes(:uris)
        end
      else
        # when not filtered by dictionaries
        expressions = Expression.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.includes(:uris)
        @dictionaries = expressions.collect{|d| d.dictionaries }.flatten.uniq
      end

      if expressions
        per_page = 30
        expression_ids = expressions.collect{|expression| expression.id }.uniq
        if dictionary_ids.present?
          expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['expression_id IN (?)', expression_ids]).where('dictionary_id IN (?)', dictionary_ids).page(params[:page])
        else
          expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['expression_id IN (?)', expression_ids]).page(params[:page])
        end
        # detect order
        if params[:order_key] == 'expression'
          order = "expressions.words #{params[:order]}"
        elsif params[:order_key] == 'id'
          order = "uris.resource #{params[:order]}"
        elsif params[:order_key] == 'dictionary'
          order = "dictionaries.title #{params[:order]}"
        else
          order = ActiveRecord::Base.send(:sanitize_sql_array, ["position(expression_id::text in '#{ expression_ids.join(',')}')"])
        end
        @expressions_uris = expressions_uris.order(order).per(per_page)
      end
    end

    respond_to do |format|
      format.html
      format.json { 
        render json: expressions_uris_to_json({expressions_uris: expressions_uris.order(order), terms: params[:terms], output: params[:output]}) 
      }
    end
  end
end
