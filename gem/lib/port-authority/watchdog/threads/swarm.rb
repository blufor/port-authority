module PortAuthority
  module Watchdog
    module Threads
      def thread_swarm
        Thread.new do
          debug '<swarm> starting thread...'
          etcd = etcd_connect!
          while !@exit do
            debug '<swarm> checking etcd state'
            status = leader? etcd
            @semaphore[:swarm].synchronize { @status_swarm = status }
            debug "<swarm> i am #{status ? 'the leader' : 'not a leader' }"
            sleep @config[:etcd][:interval]
          end
          info '<swarm> ending thread...'
        end
      end
    end
  end
end
