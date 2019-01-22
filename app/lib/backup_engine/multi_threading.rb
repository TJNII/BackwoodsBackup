require 'concurrent'

Thread.abort_on_exception = true

module BackupEngine
  module MultiThreading
    PROCESSOR_COUNT = Concurrent.processor_count.freeze

    def self.worker_pool(workers:, work_queue:)
      worker_threads = Array.new(workers) do
        Thread.new do
          loop do
            yield(work_queue.pop)
          end
        end
      end

      # Tighten the check loop delay as the queue drops
      # Hedge against the done delay slowing things down.
      sleep((work_queue.length / workers).to_i * 0.0001) until work_queue.num_waiting == workers
      raise('Concurrency failure: All workers idle with non-empty queue') unless work_queue.empty?

      worker_threads.each(&:kill)
    end
  end
end
