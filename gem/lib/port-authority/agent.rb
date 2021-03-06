require 'timeout'
require 'json'
require 'yaml'
require 'port-authority'
require 'port-authority/config'
require 'port-authority/logger'
require 'port-authority/etcd'

module PortAuthority
  # Scaffolding class for agents
  class Agent
    # Common agent process init. Contains configuration load,
    # common signal responses and runtime variables init.
    # Implements execution of actual agents via \+run+ method.
    # Also handles any uncaught exceptions.
    def initialize
      Thread.current[:name] = 'main'                        # name main thread
      @@_exit = false                                       # prepare exit flag
      @@_semaphores = { log: Mutex.new }                    # init semaphores
      @@_threads = {}                                       # init threads
      Signal.trap('INT') { exit!(1) }                       # end immediatelly
      Signal.trap('TERM') { end! }                          # end gracefully
      Config.load! || exit!(1)                              # load config or die
      begin                                                 # all-wrapping exception ;)
        run                                                 # hook to child class
      rescue StandardError => e
        Logger.alert "UNCAUGHT EXCEPTION IN THREAD main! Dying!  X.X"
        Logger.alert [' ', "#{e.class}:", e.message].join(' ')
        e.backtrace.each {|line| Logger.debug "  #{line}"}
        exit! 1
      end
    end

    # Setup the agent process.
    # Initializes logging, system process parameters,
    # daemonizing.
    #
    # There are 4 optional parameters:
    # +:name+:: \+String+ Agent name. Defaults to \+self.class.downcase+ of the child agent
    # +:root+:: \+Bool+ Require to be ran as root. Defaults to \+false+.
    # +:daemonize+:: \+Bool+ Daemonize the process. Defaults to \+false+.
    # +:nice+:: \+Int+ nice of the process. Defaults to \+0+
    def setup(args = {})
      name = args[:name] || self.class.to_s.downcase.split('::').last
      args[:root] ||= false
      args[:daemonize] ||= false
      args[:nice] ||= 0
      Logger.init! @@_semaphores[:log], name
      Logger.info 'Starting main thread'
      Logger.debug 'Setting process name'
      if RUBY_VERSION >= '2.1'
        Process.setproctitle("pa-#{name}-agent")
      else
        $0 = "pa-#{name}-agent"
      end
      if args[:root] && Process.uid != 0
        Logger.alert 'Must run under root user!'
        exit! 1
      end
      Logger.debug 'Setting CPU nice level'
      Process.setpriority(Process::PRIO_PROCESS, 0, args[:nice])
      if args[:daemonize]
        Logger.info 'Daemonizing process'
        if RUBY_VERSION < '1.9'
          exit if fork
          Process.setsid
          exit if fork
          Dir.chdir('/')
        else
          Process.daemon
        end
      end
    end

    # Has the exit flag been raised?
    def exit?
      @@_exit
    end

    # Raise the exit flag
    def end!
      @@_exit = true
    end

    # Create a named \+Mutex+ semaphore
    def sem_create(name)
      @@_semaphores.merge!(Hash[name.to_sym], Mutex.new)
    end

    # Create a named \+Thread+ with its \+Mutex+ semaphore.
    # The definition includes \+&block+ of code that should run
    # within the thread.
    #
    # The method requires 3 parameters:
    # +name+:: \+Symbol+ Thread/Mutex name.
    # +interval+:: \+Integer+ Thread loop interval.
    # +&block+:: \+Proc+ Block of code to run.
    def thr_create(name, interval, &block)
      @@_semaphores.merge!(Hash[name.to_sym, Mutex.new])
      @@_threads.merge!(Hash[name.to_sym, Thread.new do
          Thread.current[:name] = name.to_s
          Logger.info "Starting thread #{Thread.current[:name]}"
          begin
            until exit?
              yield block
              sleep interval
            end
            Logger.info "Ending thread #{Thread.current[:name]}"
          rescue StandardError => e
            Logger.alert "UNCAUGHT EXCEPTION IN THREAD #{Thread.current[:name]}"
            Logger.alert [' ', "#{e.class}:", e.message].join(' ')
            e.backtrace.each {|line| Logger.debug "  #{line}"}
            end!
          end
        end
      ])
    end

    # Run thread-safe code.
    # The \+name+ parameter can be omitted when used
    # from within a block of thread code. In this case
    # the Mutex with the same \+:name+ will be used.
    #
    # The method accepts following parameters:
    # +name+:: \+Symbol+ Mutex name.
    # +&block+:: \+Proc+ Block of code to run.
    def thr_safe(name=Thread.current[:name].to_sym, &block)
      @@_semaphores[name.to_sym].synchronize do
        yield block
      end
    end

    # Start named thread.
    # If the name is omitted, applies to all spawned threads ;)
    def thr_start(name=nil)
      return @@_threads[name].run if name
      @@_threads.each_value(&:run)
    end


    # Wait for named thread to finish.
    # If the name is omitted, applies to all spawned threads ;)
    def thr_wait(name=nil)
      return @@_threads[name].join if name
      @@_threads.each_value(&:join)
    end

    # Return hostname.
    def hostname
      @hostname ||= Socket.gethostname
    end

  end
end
