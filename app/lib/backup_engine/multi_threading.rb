require 'concurrent'

Thread.abort_on_exception = true

module BackupEngine
  module MultiThreading
    PROCESSOR_COUNT = Concurrent.processor_count.freeze

    class WorkerPool
      attr_accessor :queue

      def initialize(workers:)
        @workers = workers
        @queue = Queue.new

        @worker_threads = Array.new(workers) do
          Thread.new do
            loop do
              yield(@queue.pop)
            end
          end
        end
      end

      def join
        # Tighten the check loop delay as the queue drops
        # Hedge against the done delay slowing things down.

        # First pass: Block until the queue is empty.
        # Intended to block during initial queue pop delay and during processing
        sleep((@queue.length / @workers).to_i * 0.01) until @queue.empty?

        # Second pass: Block until all threads are idle.
        # Intended to block until threads finish processing
        sleep((@queue.length / @workers).to_i * 0.01) until @queue.num_waiting == @workers

        # This sanity predates the @queue.empty? block, leaving it as defensive code even though it should now be impossible to trigger.
        raise('Concurrency failure: All workers idle with non-empty queue') unless @queue.empty?

        @worker_threads.each(&:kill)
      end

      def process(input)
        input.each do |chunk|
          @queue << chunk
        end
      end
    end
  end
end
