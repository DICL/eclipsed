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
    # Configure {{{
    def configure
      json_conf = File.open(find_confpath) { |f| JSON.parse(f.read) }
      @nodelist = json_conf['network']['nodes']
      @app_dir = json_conf['path']['applications']
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
    # all_but {{{
    def all_but(index) 
      thr = print_async "Initializing framework..."
      i = 0
      @nodelist.each do |node|
        if i != index.to_i then
          cmd = "ssh #{node} 'export PATH=\"#{ENV['PATH']}\"; nohup eclipse_node </dev/null &>/dev/null &'"
          puts cmd if @verbose
          system cmd
        end
        i = i + 1
      end
      thr.exit
      print "\r"
    end 

    #}}}
    # restart {{{
    def restart 
      close
      launch
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
      cmd  = "ssh #{@nodelist[index.to_i]} -t \'export PATH=\"#{ENV['PATH']}\"; gdb --args eclipse_node \'"
      puts cmd 
      exec cmd
    end 
    #}}}
    # attach_at {{{
    def attach_at(index) 
      cmd  = "ssh #{@nodelist[index.to_i]} -t \"#{"sudo" if @sudo} gdb --pid \\`pgrep -u #{`whoami`.chomp} -x eclipse_node\\`\""
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
        cmd = "ssh #{node} \'pgrep -u #{`whoami`.chomp} -x eclipse_node &>/dev/null; echo $?\'"
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
    # submit {{{
    def submit(input)
      file_name = File.basename(input,File.extname(input)) 
      system "g++ -c -std=c++14 -Wall -Werror -fpic #{input}"
      system "gcc -shared -fPIC -o #{file_name}.so #{file_name}.o"
      @nodelist.each do |node|
        system "scp #{file_name}.so #{node}:#{@app_dir}/"
      end
    end #}}}
    # compile {{{
    def compile(input)
      file_name = File.basename(input,File.extname(input)) 
      system "g++ -std=c++14 -Wall -Werror -o #{file_name} #{file_name}.cc -lvdfs -lboost_system"
    end #}}}
  end

  class CLI_driver < Core
    def initialize input: #{{{
      super

      configure

      OptionParser.new do |opts|
        opts.banner = "eclipsed (Eclipse Daemon controler) is an script to manage the EclipseDFS\n" +
          "Usage: eclipsed [options] <actions> [FILE]..."
        opts.version = Eclipsed::VERSION
        opts.program_name = "Eclipse Launcher"
        opts.separator "Core actions"
        opts.separator "    launch       Create new Eclipse network"
        opts.separator "    close        Close the network"
        opts.separator "    restart      Close and create the network"
        opts.separator "    status       Check the status of the network"
        opts.separator "    kill         kill application in each node"
        opts.separator ""
        opts.separator "MapReduce actions"
        opts.separator "    submit [app]   Submit application to VeloxMR system"
        opts.separator "    compile [app]  Compile application client binary"
        opts.separator ""
        opts.separator "Debugging actions"
        opts.separator "    debug_at [N]   Launch eclipseDFS with node N in gdb"  
        opts.separator "    attach_at [N]  Attach gdb to the N node"
        opts.separator "    all_but [N]    Launch all eclipse in all nodes but one"
        opts.separator ""
        opts.separator "Options"
        opts.on_tail("-h", "--help"   , "recursive this")         { puts opts; exit}
        opts.on_tail("-v", "--verbose" , "printout verbose info") { @verbose = true }
        opts.on_tail("-V", "--version" , "printout version") { puts opts.ver; exit }
        opts.on_tail("-s", "--sudo" , "Use sudo for attach") { @sudo = true }
      end.parse! input

      case input.shift
      when 'launch' then launch
      when 'close' then  close
      when 'restart' then restart 
      when 'status' then show
      when 'kill' then   kill input
      when 'debug_at' then debug_at input[0]
      when 'attach_at' then attach_at input[0]
      when 'all_but' then all_but input[0]
      when 'submit' then submit input[0]
      when 'compile' then compile input[0]
      when 'pry' then    pry
      else            raise 'No valid argument, rerun with --help' 
      end
    end #}}}
  end

end
