require 'sinatra'
require 'sinatra/reloader'

require "sqlite3"

db = SQLite3::Database.new "opac.db"

get '/' do 
    query = "select title from books where 1"
    if ! params.fetch("keywords", "").empty?
        query += " and title like '%#{params["keywords"]}%'" 
    end
    @books = db.execute query
    print query
    erb:index
  end

get '/index.erb' do
    erb:index
end
  
get '/free_word.erb' do
    erb:free_word
end

get '/stdopt/:id/?:usr?' do |id, usr|
    "stdopt args ID:#{id} User:#{usr}"
  end

