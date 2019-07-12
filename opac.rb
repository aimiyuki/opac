require 'sinatra/base'
require 'sinatra/reloader'
require 'sqlite3'

require_relative 'models'


# open opac.db
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: File.join(File.dirname(__FILE__), 'opac.db')
)

class FixPathInfo
  def initialize(app)
    @app = app
  end

  def call(env)
    env["PATH_INFO"] = "/" if env["PATH_INFO"].nil?
    @app.call env
  end
end

class Opac < Sinatra::Base
  use FixPathInfo # Rack::Static fails if PATH_INFO is nil
  use Rack::Static, urls: ['/public']

  set :per_page, 10

  configure :development do
    register Sinatra::Reloader
  end

  def param_present?(key)
    ##
    # Checks if the parameter has been provided
    !params.fetch(key, "").empty?
  end

  def make_search
    ##
    # Executes the search with the current parameters
    # and set the @books, @page and other required variables accordingly
    @page = params.fetch(:page, "1").to_i
    @books = Book.all

    @available_years = Book.distinct.pluck(:publication_year)

    # quick search
    params.fetch(:keyword, '').split(' ').each do |keyword|
      @books = @books.with_keyword(keyword)
    end

    # advanced search
    @books = @books.with_title(params[:title]) if param_present?(:title)
    @books = @books.with_author(params[:author]) if param_present?(:author)
    @books = @books.with_publisher(params[:publisher]) if param_present?(:publisher)
    @books = @books.where(isbn: params[:isbn]) if param_present?(:isbn)
    @books = @books.where(publication_year: params[:year].to_i) if param_present?(:year)

    @hit_count = @books.count
    @last_page = (@books.count / settings.per_page.to_f).ceil

    @books = @books.limit(settings.per_page).offset((@page - 1) * settings.per_page)
  end

  def page_url(page_number)
    ##
    # Returns the current URL with the given page number
    # e.g. if the current path is /advanced-search?page=2
    # and the method is called with 3, it will return /advanced-search?page=3
    request.path_info + '?' + Rack::Utils.build_nested_query(params.merge(page: page_number))
  end

  # routes

  get '/' do
    ##
    # Index route, renders a quick search
    make_search
    erb :index
  end

  get '/advanced-search' do
    ##
    # Renders advanced search
    make_search
    erb :advanced
  end

  get '/books/:id' do
    ##
    # Renders single book
    @book = Book.find(params[:id])
    erb :book
  end

  # only run if script is called directly
  # in case it is run within CGI, this line will not be executed
  run! if app_file == $0
end
