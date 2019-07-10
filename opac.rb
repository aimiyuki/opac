require 'sinatra/base'
require 'sinatra/reloader'
require 'sqlite3'


class Opac < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  def initialize
    super
    @db = SQLite3::Database.new "opac.db"
  end

  get '/' do
    query = "select title from books where 1"
    if ! params.fetch("keywords", "").empty?
      query += " and title like '%#{params["keywords"]}%'" 
    end
    @books = @db.execute query
    print query
    erb :index
  end

  get '/free-word' do
    erb :free_word
  end

  run! if app_file == $0
end
