#!/usr/bin/ruby

require 'set'
require 'sqlite3'


##
# Mapping to a normalized role name
# for the authors, as the raw data contain
# the authors in forms such as '川本英明訳'
ROLES = {
  '編著' => 'editor',
  '監修' => 'director',
  '編' => 'editor',
  '著' => 'author',
  '訳' => 'translator',
  '絵' => 'illustrator',
}

##
# Keys from the raw data which can be repeated more
# than once for a single book
REPEATED_KEYS = [:authorheading, :note]

db = SQLite3::Database.new "opac.db"

rows = db.execute_batch <<-SQL
  create table if not exists holding_locations (
    id integer primary key autoincrement,
    name varchar(1024)
  );

  create table if not exists books (
    id integer primary key autoincrement,
    holding_location_id integer not null,
    holding_record varchar(1024) not null,
    nbc varchar(30),
    isbn varchar(30),
    title varchar(1024) not null,
    publisher varchar(1024),
    published_location varchar(1024),
    publication_year integer,
    publication_month integer,
    page_count integer,
    height integer,
    width integer,
    foreign key (holding_location_id) references holding_locations(id)
  );

  create table if not exists authors (
    id integer primary key autoincrement,
    full_name varchar(1024) not null,
    first_name varchar(1024),
    last_name varchar(1024),
    first_name_kana varchar(1024),
    last_name_kana varchar(1024)
  );

  create table if not exists book_authors (
    book_id integer,
    author_id integer,
    role string,
    primary key (book_id, author_id, role),
    foreign key (book_id) references books(id),
    foreign key (author_id) references authors(id)
  );

  create table if not exists notes (
    id integer primary key autoincrement,
    book_id integer,
    content text,
    foreign key (book_id) references books(id)
  );

  -- JOIN related indexes
  create index if not exists book_authors_book_id on book_authors(book_id);
  create index if not exists book_authors_author_id on book_authors(author_id);
  create index if not exists notes_book_id on notes(book_id);
  create index if not exists book_holding_location_id on books(holding_location_id);

  -- search indexes
  create index if not exists books_isbn on books(isbn);
  create index if not exists books_isbn on books(nbc);
  create index if not exists books_publication_year on books(publication_year);
  create index if not exists books_publication_month on books(publication_month);
SQL


def strip_parenthesis(string)
  ##
  # Removes parenthesis [] from a string
  # and strip all white spaces
  # " [ foo]  " -> "foo"
  string = string.strip
  string = string[1..-1] if string.start_with?("[")
  string = string[0..-2] if string.end_with?("]")
  string.strip
end

def parse_author_heading(heading)
  ##
  # Parses a line of authorheading
  # and returns the result as first_name and last_name

  # if there is no parenthesis, the name does not have kana
  # and is probably a name in romaji
  if !heading.include?(" (")
    last_name, first_name = heading.split(", ")
    return { last_name: last_name, first_name: first_name }
  end

  kana, name = heading.split(" (")
  name = name[0...-1] unless name.nil?  # remove closing parenthesis
  last_name_kana, first_name_kana = kana.split(", ")
  last_name, first_name = name.split(", ")
  { last_name_kana: last_name_kana , first_name_kana: first_name_kana,
    last_name: last_name, first_name: first_name }
end


def parse_author(raw_author, book)
  ##
  # Parses the authors of the book
  # If the author has a particular role (e.g. 訳)
  # the role will be returned as well
  # if the role is not found, "author" will be returned as the default role
  # the result is returned as { author: { name: name }, role: role }
  author_name = raw_author.gsub("[", "").gsub("]", "").strip
  role = "author"
  ROLES.each do |name, normalized_name|
    if author_name.end_with?(name)
      author_name = author_name[0...-name.length]
      role = normalized_name
      break
    end
  end
  author_name = strip_parenthesis(author_name)
  author = { full_name: author_name }
  book[:authorheading].each do |raw_heading|
    heading = parse_author_heading(raw_heading)
    if author_name.include?(heading[:last_name])
      author = author.merge(heading)
      break
    end
  end
  { author: author, role: role }
end

def parse_authors(raw_authors, book)
  ##
  # Parses a list of authors
  # The authors are assumed to be separated by " ; " or "，"
  return [] if raw_authors.nil?
  raw_authors.split(/ ; |，|,/).map { |raw_author| parse_author(raw_author, book) }
end

def parse_tr(book)
  ##
  # Parses a TR: line
  # Returns the title and an array of authors as result
  # The title and the authors are assumed to be separated by " / "
  title, all_authors = book[:tr].split(" / ")
  { title: title.strip, authors: parse_authors(all_authors, book) }
end

def parse_date(raw_date)
  ##
  # Extracts the date from a raw_date
  # supports format such as
  # 2004.8
  # 2004
  # c2004
  # [2004.8]
  # returns the result as { year: year, month: month }
  # if the month is not given, { year: year } will be returned
  year, month = raw_date[/[0-9]{2,4}(\.[0-9]{1,2})?/].split(".")
  date = { year: year.to_i }
  date[:month] = month.to_i unless month.nil?
  date
end

def parse_pub(raw_pub)
  ##
  # Parses a PUB: line
  # returns the result as
  # { location: location, publisher: publisher, year: year, month: month }

  raw_pub_info, raw_date = raw_pub.split(", ")
  date = parse_date(raw_date)
  raw_location, raw_publisher = raw_pub_info.split(" : ")
  location = strip_parenthesis(raw_location)
  publisher = strip_parenthesis(raw_publisher)
  { location: location, publisher: publisher }.merge(date)
end

def parse_phys(raw_phys)
  ##
  # Parses a PHYS: line
  # returns the result as
  # { page_count: page_count, width: width, height: height }
  raw_page_count, dimensions = raw_phys.split(" ; ")
  page_count_match = /([0-9]+)p/.match(raw_page_count)
  result = {}
  result[:page_count] = page_count_match[1].to_i unless page.nil?
end

def parse_book(book)
  ##
  # Parses all the raw metadata of the book
  # and returns a hash containinng all the information
  # about the book which needs to be added to the database
  # The resulting hash will contain the results of `parse_pub` and `parse_tr`
  book = book.merge(parse_tr(book))
  book = book.merge(parse_pub(book[:pub]))
  book = book.merge(parse_bhys(book[:phys]))
  book
end


def make_empty_book
  ##
  # Create an empty book
  # where all the repeated keys (e.g. authorheading) are initialized
  # with an empty array
  book = {}
  REPEATED_KEYS.each { |key| book[key] = [] }
  book
end

def read_file(filename)
  ##
  # Reads the given file in the jbisc.txt format
  # Returns an array of hashes containing the book metadata
  books = []
  book = make_empty_book

  File.foreach(filename) do |line|
    line = line.chomp
    key, value = line.split(": ", 2)

    # if we find a "*", the current book is over
    # add it to the results and get on the next one
    if key == "*"
      books << book
      book = make_empty_book
    else
      key = key.downcase.to_sym

      # if the key is repeated, append the result
      # otherwise, simply set it
      if REPEATED_KEYS.include?(key)
        book[key] << value
      else
        book[key] = value
      end
    end
  end

  books.map { |book| parse_book(book) }
end

def get_unique_authors(books)
  ##
  # Returns a list of unique authors
  # The returned value is a set of author hashes
  authors = Set.new
  books.each do |book|
    book.fetch(:authors, []).each { |author| authors << author[:author] }
  end
  authors
end

def insert_authors(db, books)
  ##
  # Inserts all the book authors in the database
  # returns a mapping from each author to his id
  # this could wrongly assign the same id to two authors with
  # the same name/kana
  unique_authors = get_unique_authors(books)
  authors_mapping = {}

  db.transaction
  unique_authors.each do |author|
    db.execute "insert into authors (full_name, first_name, last_name, first_name_kana, last_name_kana)
                values (?, ?, ?, ?, ?)", [
                  author[:full_name], author[:first_name], author[:last_name],
                  author[:first_name_kana], author[:last_name_kana]]
    authors_mapping[author] = db.last_insert_row_id
  end
  db.commit

  authors_mapping
end

def insert_book(db, book, authors_mapping)
  ##
  # Inserts the given book in the database
  # also inserts the book-author relations in the book_authors table
  # It assumes that the authors are already present in the database
  # and that the authors_mapping contains a mapping from a (Ruby) hash of the author to the DB id of author
  columns = %w(holding_location_id holding_record isbn nbc title publisher
               published_location publication_year publication_month)
  columns_str = columns.join(", ") # "isbn, nbc, ...., publication_month"
  placeholders = Array.new(columns.size, "?").join(", ") # "?, ?, ..., ?" matching the numbers of columns

  db.execute "insert into books (#{columns_str}) values (#{placeholders})", [
    book[:location_id], book[:holdingsrecord], book[:isbn], book[:nbc],
    book[:title], book[:publisher], book[:location], book[:year], book[:month]
  ]
  book_id = db.last_insert_row_id

  # insert all notes for the book
  book.fetch(:note, []).each do |note|
    db.execute "insert into notes (book_id, content) values (?, ?)", [book_id, note]
  end

  # insert all the relations for the authors
  book.fetch(:authors, []).each do |author|
    author_id = authors_mapping[author[:author]]
    db.execute "insert into book_authors (book_id, author_id, role) values (?, ?, ?)", [
      book_id, author_id, author[:role]
    ]
  end
end

def insert_holding_locations(db, books)
  ##
  # Insert the holding location of the books
  db.transaction
  locations_mapping = {}
  books.each do |book|
    location = book[:holdingloc]
    if locations_mapping.include?(location)
      book[:location_id] = locations_mapping[location]
    else
      db.execute "insert into holding_locations (name) values (?)", [location]
      book[:location_id] = db.last_insert_row_id
      locations_mapping[location] = db.last_insert_row_id
    end
  end
  db.commit
end

def insert_books(db, books, authors_mapping)
  ##
  # Insert all the books in the database using `insert_book`
  db.transaction
  books.each { |book| insert_book(db, book, authors_mapping) }
  db.commit
end

books = read_file("jbisc.txt")
authors_mapping = insert_authors(db, books)
insert_holding_locations(db, books)
insert_books(db, books, authors_mapping)

puts "Inserted #{books.size} books and #{authors_mapping.size} authors"
