require 'active_record'

class HoldingLocation < ActiveRecord::Base
  has_many :books
end

class Book < ActiveRecord::Base
  has_many :book_authors
  has_many :authors, through: :book_authors
  has_many :notes
  belongs_to :holding_location
end

class Author < ActiveRecord::Base
  has_many :book_authors
  has_many :books, through: :book_authors
end

class BookAuthor < ActiveRecord::Base
  belongs_to :book
  belongs_to :author
end

class Note < ActiveRecord::Base
  belongs_to :author
end
