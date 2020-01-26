require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'active_support/core_ext/integer/time'

require './lib/printer_discovery'
require './lib/print_client'

set :haml, :format => :html5
enable :sessions

printers = []
semaphore = Mutex.new

thread = Thread.new do |t|
  while true
    semaphore.synchronize do
      printers = PrinterDiscovery.discover!
    end
    sleep 120
  end
end

get '/' do
  semaphore.synchronize do
    @printers = printers.dup
  end
  haml :index
end

post '/' do
  PrintClient.print(params.dup)
  params.each do |k,v|
    session[k] = v
  end
  redirect '/', 303
end