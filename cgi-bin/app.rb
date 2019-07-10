#!/usr/bin/env ruby

require_relative '../opac.rb'

Rack::Handler::CGI.run Opac.new
