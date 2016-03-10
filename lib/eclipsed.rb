require "eclipsed/version"
require 'optparse'          # For parsing the options
require 'json'              # 
require 'awesome_print'     # Pretty-printer
require 'table_print'       # Pretty-printer

module Eclipsed
  # print_async {{{
  def print_async(msg) 
    Thread.new(msg) do |m|
      print "#{m} "
      loop do
        print "\b\\"
        sleep 0.3
        print "\b-"
        sleep 0.3
        print "\b/"
        sleep 0.3
      end
    end
  end
  #}}}

  class Core 
    include Eclipsed
    # Initialize {{{
    def initialize 
      @nodelist = File.open(find_confpath) { |f| JSON.parse(f.read) }['network']['nodes']
      @verbose  = false
    end

    # }}}
  # find_confpath {{{
  def find_confpath
    home = "#{ENV['HOME']}/.eclipse.json"
    etc  = "/etc/.eclipse.json"

    if File.exists? home
      return home
    elsif File.exists? etc
      return etc
    end 
  end
  # }}}
    # launch {{{
    def launch
      thr = print_async "Initializing framework..."
      @nodelist.each do |node|
        cmd = "ssh #{node} 'export PATH=\"#{ENV['PATH']}\"; nohup eclipse_node </dev/null &>/dev/null &'"
        puts cmd if @verbose
        system cmd
      end
      thr.exit
      print "\r"
    end 

    #}}}
    # debug_at {{{
    def debug_at(index) 
      i = 0
      @nodelist.each do |node|
        if i != index.to_i then
          cmd = "ssh #{node} 'export PATH=\"#{ENV['PATH']}\"; nohup eclipse_node </dev/null &>/dev/null & exit'"
          puts cmd
          system cmd
        end
        i = i + 1
      end
      cmd  = "ssh #{@nodelist[index.to_i]} \'export PATH=\"#{ENV['PATH']}\"; gdb --args eclipse_node \'"
      puts cmd 
      exec cmd
    end 
    #}}}
    # show {{{
    def show 
      msg_handler = print_async "Collecting information..."

      instance = [ ]
      in_english = { true => "Running", false => "Stopped" }

      status = nil
      @nodelist.each do |node|
        out = nil
        cmd = "ssh #{node} \'pgrep -x eclipse_node &>/dev/null; echo $\'"
        puts cmd if @verbose
        if `#{cmd}`.chomp == '0'
          out = true 
        else
          out = false
        end
        mr_status    = in_english[out]
        instance << { :host => node, :status => mr_status, :role => "worker" }
      end

      msg_handler.exit
      print "\r"
      tp instance, "host", "role", "status"
    end 

    #}}}
    # close {{{
    def close
      thr = print_async "Stopping framework..."
      @nodelist.each do |node|
        `ssh #{node} pkill -u #{`whoami`.chomp} eclipse_node`
      end 
      thr.exit
      print "\r"
    end #}}}
    # kill {{{
    def kill(input)
      @nodelist.each do |node|
        cmd = "ssh #{node} \'pkill -u #{`whoami`.chomp} #{input.join}\'"
        puts cmd if @verbose
        system cmd
      end
    end #}}}
    # pry {{{
    def pry 
      require 'pry'
      binding.pry
    end #}}}
  end

  class CLI_driver < Core
    def initialize input:  #{{{
      @options = {}
      super()
      OptionParser.new do |opts|
        opts.banner = "eclipsed (Eclipse Daemon controler) is an script to manage the EclipseDFS\n" +
          "Usage: eclipsed [options] <actions> [FILE]..."
        opts.version = 1.0
        opts.program_name = "Eclipse Launcher"
        opts.separator "Core actions"
        opts.separator "    launch       Create new Eclipse network"
        opts.separator "    close        Close the network"
        opts.separator "    status       Check the status of the network"
        opts.separator "    kill         kill application in each node"
        opts.separator ""
        opts.separator "Options"
        opts.on_tail("-h", "--help"   , "recursive this")         { puts opts; exit}
        opts.on_tail("-v", "--verbose" , "printout verbose info") { @verbose = true }
        opts.on_tail("-V", "--version" , "printout version") { puts opts.ver; exit }
      end.parse! input

      case input.shift
      when 'launch' then launch
      when 'close' then  close
      when 'status' then show
      when 'kill' then   kill input
      when 'debug_at' then debug_at input[0]
      when 'pry' then    pry
      else               raise "Not action given"
      end
    end #}}}
  end

end
