#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require "sqlite3"

db = SQLite3::Database.new "opac.db"

rows = db.execute <<-SQL
  create table if not exists books (
    id integer primary key autoincrement,
    nbc varchar(30),
    isbn varchar(30),
    title varchar(1024)
  );
  create table if not exists authors (
    id integer primary key autoincrement,
    name varchar(1024)
  );
SQL

nbc = ""
io = open("jbisc.txt", "r")

books = []
book = {}

while true
  line = io.gets

  if line == nil
    break
  end

  line = line.chomp
  key, value = line.split(": ", 2)
  if key == "*"
    books << book
    book = {}
  else
    book[key.downcase] = value
  end

  if books.size == 10
    break
  end
end

io.close

def format_book(book)
  title, all_authors = book["tr"].split(" / ")
  book["title"] = title
  book
end

def insert_book(db, book)
  db.execute "insert into books (isbn, nbc, title) values (?, ?, ?)", [book["isbn"], book["nbc"], book["title"]]
end

books = books.map { |book| format_book(book) }
books.each { |book| insert_book(db, book) }
