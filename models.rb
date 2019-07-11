require 'active_record'

# reverse mapping for the roles assigned in create_database.rb
ROLES = {
 'editor' => '編著',
 'director' => '監修',
 'author' => '著',
 'translator' => '訳',
 'illustrator' => '絵',
}


class HoldingLocation < ActiveRecord::Base
  has_many :books
end

class Book < ActiveRecord::Base
  has_many :book_authors
  has_many :authors, through: :book_authors
  has_many :notes
  belongs_to :holding_location

  # this is needed for where query on the authors
  default_scope { includes(:authors).references(:author) }

  def holding_location_name
    holding_location.name
  end

  def publication_date
    result = publication_year.to_s
    result += "-#{publication_month}" if !publication_month.nil? && publication_month > 0
    result
  end

  def size
    result = ""
    result += "#{width}x" if !width.nil? && width > 0
    result += "#{height}cm" if !height.nil? && height > 0
    result
  end

  ##
  # the methods below are class/table-level filters to search in the database

  def self.filter_with(key, value)
    case key
    when :keyword then with_keyword(value)
    when :title then with_title(value)
    when :author then with_author(value)
    when :publisher then with_publisher(value)
    else all
    end
  end

  def self.with_keyword(keyword)
    with_title(keyword).or(with_author(keyword)).or(with_publisher(keyword)) \
                       .or(where(publication_year: keyword.to_i)) \
                       .or(where(isbn: keyword))
  end

  def self.with_title(name)
    where(arel_table[:title].matches("%#{name}%"))
  end

  def self.with_author(name)
    where(Author.arel_table[:full_name].matches("%#{name}%"))
  end

  def self.with_publisher(name)
    where(arel_table[:publisher].matches("%#{name}%"))
  end
end

class Author < ActiveRecord::Base
  has_many :book_authors
  has_many :books, through: :book_authors
end

class BookAuthor < ActiveRecord::Base
  belongs_to :book
  belongs_to :author

  def formatted
    result = author.full_name
    if role != "author"
      result += formatted_role
    end
    result
  end

  def formatted_role
    ROLES.fetch(role, "")
  end
end

class Note < ActiveRecord::Base
  belongs_to :author
end
