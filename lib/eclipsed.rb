require "eclipsed/version"
require 'optparse'          # For parsing the options
require 'json'              # 
require 'ffi'               # For loading C functions, in this case the hash functions
require 'awesome_print'     # Pretty-printer
require 'table_print'       # Pretty-printer

module Eclipsed
  module EclipseAPI  #{{{
    extend FFI::Library
    ffi_lib "libecfs.so"
    attach_function :hash_ruby, [ :string ], :uint32
  end
  #}}} 
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
    # set_fs_variables {{{

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
      `master &>/dev/null &`
      sleep 1
      @nodelist.each do |node|
        system "ssh #{node} 'nohup slave </dev/null &>/dev/null & exit'"
      end
      thr.exit
      print "\r"
    end 

    #}}}
    # show {{{
    def show 
      msg_handler = print_async "Collecting information..."

      instance = [ ]
      in_english = { true => "Running", false => "Stopped" }

      cmd = "pgrep -u #{`whoami`.chomp} master &>/dev/null"
      puts cmd if @verbose
      status = in_english[system cmd]
      instance << { :host => "localhost", :status => status, :role => "master" }

      @nodelist.each do |node|
        mr_status    = in_english[system "ssh #{node} pgrep -u #{`whoami`.chomp} -x slave &>/dev/null"]
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
      `pkill -u #{`whoami`.chomp} master`
      @nodelist.each do |node|
        `ssh #{node} pkill -u #{`whoami`.chomp} slave`
      end 
      thr.exit
      print "\r"
    end #}}}
    # submit {{{
    def submit(input)
    #  @instance[:app]= input
    #  File.open(@fs_tmpfile, 'w') { |f| f.write(JSON.generate(@instance)) }

      system input.join(' ')
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

  class Fs < Core
    include EclipseAPI
    def initialize #{{{
      @files           = {}
      @config          = File.open(find_confpath) { |f| JSON.parse(f.read) }
      @fs_path         = @config['path']['filesystem']
      @fs_scratch_path = @config['path']['scratch']
      @fs_tmpfile      = @fs_path + "/.list"
      @files           = File.open(@fs_tmpfile) { |f| JSON.parse(f.read) } if File.exist? @fs_tmpfile
      alias :hash :hash_ruby
      super()
    end

    def node_containing(fn); @nodelist[hash(fn) % @nodelist.length] end

    #}}}
    # put {{{
    def put(input)
      input.each do |fn|
        node = node_containing(fn)
        @files[fn] = node

        File.open(@fs_tmpfile, 'w') { |f| f.write(JSON.generate(@files)) }
        cmd = "scp #{@fs_path}/#{fn} #{node}:#{@fs_scratch_path}/#{fn}"
        puts cmd if @verbose
        system cmd
      end
    end

    #}}}
    # cat {{{
    def cat(input)
      input.each do |fn|
        system "ssh #{node_containing(fn)} cat #{@fs_scratch_path}/#{fn}"
      end
    end

    #}}}
    # get {{{
    def get(input)
      input.each do |fn|
        cmd = "scp #{node_containing(fn)}:#{@fs_scratch_path}/#{fn} ."
        puts cmd if @verbose
        system cmd
      end
    end

    #}}}
    # rm {{{
    def rm(input)
      input = @files.keys.grep(%r[#{@regex}]) if @regex

      input.each do |fn|
#        raise "\'#{fn}\' not found in Eclipse FS" unless @files[fn]

        node = node_containing(fn)
        pathtofile = @fs_scratch_path + "/" + fn
        cmd = "ssh #{node} rm -f #{pathtofile}"
        puts cmd if @verbose
        system cmd
        @files.delete(fn)
        File.open(@fs_tmpfile, 'w') { |f| f.write(JSON.generate(@files)) }
      end
    end

    #}}}
    def list #{{{
      thr = print_async "Collecting information..."
      output = [ ] 
      @files.each{|k, v| output << { :filename => k, :location => v} }

      @nodelist.each do |node| 
        `ssh #{node} ls #{@fs_scratch_path}`.each_line do |l| 
          l.chomp!
          output << { :filename => l, :location => node} unless @files.has_key?(l)
        end
      end

      thr.exit
      print "\r\e[K" 
      tp output, :filename, :location
    end

    #}}}
    def config #{{{
      ap self.instance_variables.map{|var|  [var, self.instance_variable_get(var)]}.to_h
    end  #}}}
    # compile {{{
    def compile(input)
      sources = input.join(' ')
      raise 'Need to specify output file (-o File)' unless @outputfile 

      cmd = "#{CXX} -static -o #{@outputfile} #{sources} -l ecfs"
      puts cmd if @verbose
      system cmd
    end

    #}}}
    def clear #{{{
      rm @files.keys
      @nodelist.each do |node|
        cmd = "ssh #{node} rm -rf #{@fs_scratch_path}/.job* #{@fs_scratch_path}/*"
        puts cmd if @verbose
        system cmd
      end
    end
    #}}}
  end

  class CLI_driver < Fs 
    def initialize input:  #{{{
      @options = {}
      super()
      OptionParser.new do |opts|
        opts.banner = "ecfs (Eclipse FileSystem) is an script to manage the fs\n" +
          "Usage: ecfs [options] <actions> [FILE]..."
        opts.version = 1.0
        opts.program_name = "Eclipse Launcher"
        opts.separator "Core actions"
        opts.separator "    launch       Create new Eclipse network"
        opts.separator "    close        Close the network"
        opts.separator "    status       Check the status of the network"
        opts.separator "    submit       Submit application"
        opts.separator "    kill         kill application in each node"
        opts.separator ""
        opts.separator "Filesystem actions"
        opts.separator "    put FILE...  insert FILE..."
        opts.separator "    get FILE...  copy the FILES to the current directory"
        opts.separator "    rm FILE...   remove FILE..."
        opts.separator "    cat FILE...  \'cat\' the FILE..."
        opts.separator "    clear        remove all the files in the FS"
        opts.separator "    ls           list all the files in the FS"
        opts.separator "    config       list all the internal variables"
        opts.separator "    cc -o OUTPUT INPUT...  Compile file with EclipseFS API using OUTPUT name"
        opts.separator ""
        opts.separator "Options"
        opts.on_tail("-h", "--help"   , "recursive this")         { puts opts; exit}
        opts.on_tail("-v", "--verbose" , "printout verbose info") { @verbose = true }
        opts.on_tail("-V", "--version" , "printout version") { puts opts.ver; exit }
        opts.on_tail("-o FILE", "output file, for mcc") { |f| @outputfile = f }
        opts.on_tail("-r REGEX", "regex for remove or ls") { |r| @regex = r }
      end.parse! input

      case input.shift
      when 'launch' then launch
      when 'close' then  close
      when 'status' then show
      when 'submit' then submit input
      when 'kill' then   kill input
      when 'put' then    put input
      when 'get' then    get input
      when 'cat' then    cat input
      when 'rm' then     rm input
      when 'clear' then  clear
      when 'ls' then     list
      when 'config' then config 
      when 'cc' then     compile(input)
      when 'pry' then    pry
      else               raise "Not action given"
      end
    end #}}}
  end

end
