require 'logger'
require 'securerandom'
require_relative '../../../spec_helper.rb'

require_relative '../../../../lib/backup_engine/communicator_backend/s3_list_cache.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::CommunicatorBackend::S3ListCache do
    shared_examples 'cache behavior' do
      let(:test_obj) { described_class.new(**test_config) { |_| nil } }

      describe 'add' do
        it 'adds to the cache' do
          test_obj.add(path: 'foo/bar', date: 100)
          test_obj.add(path: 'foo/baz', date: 200)
          test_obj.add(path: 'bar/baz', date: 300)

          expect(test_obj.cache['/foo/bar']).to eql(100)
          expect(test_obj.cache['/foo/baz']).to eql(200)
          expect(test_obj.cache['/bar/baz']).to eql(300)
        end

        it 'applies the date to all lower keys' do
          test_obj.add(path: 'foo/bar/baz', date: 100)
          expect(test_obj.cache['/foo/bar/baz']).to eql(100)
          expect(test_obj.cache['/foo/bar']).to eql(100)
          expect(test_obj.cache['/foo']).to eql(100)
        end

        it 'updates lower keys without discarding data' do
          test_obj.add(path: 'foo/bar', date: 100)
          test_obj.add(path: 'foo/baz', date: 200)
          test_obj.add(path: 'foo', date: 300)

          expect(test_obj.cache['/foo/bar']).to eql(100)
          expect(test_obj.cache['/foo/baz']).to eql(200)
          expect(test_obj.cache['/foo']).to eql(300)
        end

        it 'propagates the newest date down' do
          test_obj.add(path: 'foo/bar/baz', date: 300)
          test_obj.add(path: 'foo/bar', date: 200)
          test_obj.add(path: 'foo', date: 100)

          expect(test_obj.cache['/foo/bar/baz']).to eql(300)
          expect(test_obj.cache['/foo/bar']).to eql(300)
          expect(test_obj.cache['/foo']).to eql(300)
        end
      end

      describe 'cache' do
        it 'is immutable' do
          expect { test_obj.cache['foo'] = nil }.to raise_exception(FrozenError)
        end
      end

      describe 'children' do
        before :each do
          test_obj.add(path: 'foo/bar/baz/foobar/barbaz', date: 100)
          test_obj.add(path: 'foo/bar/baz/foobaz/barbaz', date: 100)
          test_obj.add(path: 'foo/bar1/baz/foobar/barbaz', date: 100) # Test for end_index bug
          test_obj.add(path: 'foo/bar1/baz/foobaz/barbaz', date: 100) # Test for end_index bug
          test_obj.add(path: 'bar', date: 300)
          test_obj.add(path: 'baz', date: 200)
        end

        it 'returns the child list on empty path with default args' do
          expect(test_obj.children(path: '/')).to eq(%w[foo bar baz].sort.map { |p| BackupEngine::Pathname.new(p) })
        end

        it 'raises exception on unknown key' do
          expect { test_obj.children(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
        end

        it 'returns an empty list for a path with no children' do
          expect(test_obj.children(path: 'baz')).to eq([])
        end

        describe 'when fully_qualified enabled' do
          let(:fully_qualified) { true }

          it 'returns nested child lists' do
            tgt_paths = %w[foo/bar/baz/foobar foo/bar/baz/foobaz]
            expect(test_obj.children(path: 'foo/bar/baz', fully_qualified: fully_qualified)).to eq(tgt_paths.sort.map { |p| BackupEngine::Pathname.new(p) })
          end

          it 'returns child paths to the specified depth' do
            tgt_paths = %w[foo/bar/baz/foobar/barbaz foo/bar/baz/foobaz/barbaz]
            expect(test_obj.children(path: 'foo/bar/baz', depth: 2, fully_qualified: fully_qualified)).to eq(tgt_paths.sort.map { |p| BackupEngine::Pathname.new(p) })
          end

          it 'returns all child paths with a depth of -1' do
            tgt_paths = %w[foo/bar/baz foo/bar/baz/foobar foo/bar/baz/foobar/barbaz foo/bar/baz/foobaz foo/bar/baz/foobaz/barbaz]
            expect(test_obj.children(path: 'foo/bar', depth: -1, fully_qualified: fully_qualified)).to eq(tgt_paths.sort.map { |p| BackupEngine::Pathname.new(p) })
          end
        end

        describe 'when fully_qualified disabled' do
          let(:fully_qualified) { false }

          it 'returns nested child lists' do
            tgt_paths = %w[foobar foobaz]
            expect(test_obj.children(path: 'foo/bar/baz', fully_qualified: fully_qualified)).to eq(tgt_paths.sort.map { |p| BackupEngine::Pathname.new(p) })
          end

          it 'returns child paths to the specified depth' do
            tgt_paths = %w[foobar/barbaz foobaz/barbaz]
            expect(test_obj.children(path: 'foo/bar/baz', depth: 2, fully_qualified: fully_qualified)).to eq(tgt_paths.sort.map { |p| BackupEngine::Pathname.new(p) })
          end

          it 'returns all child paths with a depth of -1' do
            tgt_paths = %w[baz baz/foobar baz/foobar/barbaz baz/foobaz baz/foobaz/barbaz]
            expect(test_obj.children(path: 'foo/bar', depth: -1, fully_qualified: fully_qualified)).to eq(tgt_paths.sort.map { |p| BackupEngine::Pathname.new(p) })
          end
        end
      end

      describe '.date' do
        it 'raises exception unknown key' do
          expect { test_obj.date(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
        end

        it 'returns child dates' do
          test_obj.add(path: 'foo/bar', date: 100)
          test_obj.add(path: 'foo/baz', date: 200)
          test_obj.add(path: 'bar/baz', date: 300)

          expect(test_obj.date(path: 'foo/bar')).to eql(Time.at(100))
          expect(test_obj.date(path: 'foo/baz')).to eql(Time.at(200))
          expect(test_obj.date(path: 'bar/baz')).to eql(Time.at(300))
        end
      end

      describe 'delete' do
        it 'empties the cache on empty path' do
          test_obj.add(path: 'foo/bar/baz/foobar', date: 100)
          test_obj.delete(path: '')
          expect(test_obj.cache).to be_empty
        end

        it 'raises exception unknown key' do
          expect { test_obj.delete(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
        end

        it 'recursively deletes child lists and empty parents' do
          test_obj.add(path: 'foo/bar/baz/foobar', date: 100)
          test_obj.add(path: 'foo/baz/foobar', date: 200)

          test_obj.delete(path: 'foo/bar/baz')
          expect(test_obj.cache.keys.sort).to eql %w[/ /foo /foo/baz /foo/baz/foobar]
        end
      end

      describe 'exists?' do
        it 'returns false on unknown key' do
          expect(test_obj.exists?(path: 'unknown/key')).to be false
        end

        it 'returns true for known children' do
          test_obj.add(path: 'foo/bar', date: 100)
          test_obj.add(path: 'foo/baz', date: 200)
          test_obj.add(path: 'bar/baz', date: 300)

          expect(test_obj.exists?(path: 'foo/bar')).to be true
          expect(test_obj.exists?(path: 'foo/baz')).to be true
          expect(test_obj.exists?(path: 'bar/baz')).to be true
        end
      end

      describe '.index' do
        it 'contains a sorted list of cache keys' do
          expect(test_obj.index).to eq(test_obj.cache.keys.sort)
        end

        it 'updates after add' do
          test_obj.add(path: 'foo', date: 100)
          expect(test_obj.index).to eq(%w[/ /foo])

          test_obj.add(path: 'foo/bar', date: 200)
          expect(test_obj.index).to eq(%w[/ /foo /foo/bar])
        end

        it 'in sync after delete' do
          test_obj.add(path: 'foo/bar/baz/foobar', date: 100)
          test_obj.add(path: 'foo/baz/foobar', date: 200)

          test_obj.delete(path: 'foo/bar/baz')
          expect(test_obj.index).to eq test_obj.cache.keys.sort
        end
      end

      describe 'Cache Seeding' do
        let(:seed_values) { Array.new(10) { [Array.new(3) { SecureRandom.hex }.join('/'), rand(0..1000)] }.to_h }

        let(:test_obj) do
          described_class.new(**test_config) do |cache_obj|
            # Test: Cache should never seed unless empty
            raise('Attempted to seed non-empty cache') unless cache_obj.cache.empty?

            seed_values.each_pair do |path, date|
              cache_obj.add(path: path, date: date)
            end
          end
        end

        let(:incomplete_loader) do
          described_class.new(**test_config) do |cache_obj|
            # Write a single value to ensure the backend object exists
            cache_obj.add(path: seed_values.keys[0], date: seed_values.values[0])
            raise('Oh bother')
          end
        end

        describe '.date' do
          it 'Seeds cold caches' do
            seed_values.each_pair do |path, date|
              expect(test_obj.date(path: path)).to eq Time.at(date)
            end
          end

          it 'Does not seed caches with values' do
            test_obj.add(path: 'foo/bar', date: 100)
            seed_values.keys.each do |path|
              expect { test_obj.date(path: path) }.to raise_exception(Errno::ENOENT)
            end
          end

          it 'Seeds after incomplete loads' do
            expect { incomplete_loader.exists?(path: 'kerboom') }.to raise_exception(StandardError)
            seed_values.each_pair do |path, date|
              expect(test_obj.date(path: path)).to eq Time.at(date)
            end
          end
        end

        describe '.exists' do
          it 'Seeds cold caches' do
            seed_values.keys.each do |path|
              expect(test_obj.exists?(path: path)).to eq true
            end
          end

          it 'Does not seed caches with values' do
            test_obj.add(path: 'foo/bar', date: 100)
            seed_values.keys.each do |path|
              expect(test_obj.exists?(path: path)).to eq false
            end
          end

          it 'Seeds after incomplete loads' do
            expect { incomplete_loader.exists?(path: 'kerboom') }.to raise_exception(StandardError)
            seed_values.keys.each do |path|
              expect(test_obj.exists?(path: path)).to eq true
            end
          end
        end
      end

      describe 'Thread Safety' do
        before :each do
          test_obj.add(path: 'foo/bar/baz/foobar/barbaz', date: 100)
          test_obj.add(path: 'foo/bar/baz/foobaz/barbaz', date: 100)
          test_obj.add(path: 'bar', date: 300)
          test_obj.add(path: 'baz', date: 200)
        end

        let(:collission_count) { 1000 } # Number of iterations expected to trigger a race condition

        let(:add_thread) do
          Thread.new do
            loop do
              test_obj.add(path: "add_thread/#{SecureRandom.hex}", date: 500)
              sleep(0.000001) # Without this the other threads can't obtain a lock in a timely manner
            end
          end
        end

        let(:delete_paths) do
          Array.new(collission_count) do |count|
            path = "delete_path/#{count}"
            test_obj.add(path: path, date: 500)
            path
          end
        end

        let(:delete_thread) do
          Thread.new do
            delete_paths.each do |path|
              test_obj.delete(path: path)
            end
          end
        end

        after :each do
          add_thread.kill
          delete_thread.kill
        end

        describe '.add/.children' do
          it 'do not conflict' do
            tgt_paths = %w[foobar foobaz].sort.map { |p| BackupEngine::Pathname.new(p) }

            add_thread
            collission_count.times do
              expect(test_obj.children(path: 'foo/bar/baz')).to eq(tgt_paths.sort)
            end
          end
        end

        describe '.add/.delete' do
          it 'do not conflict' do
            add_thread
            delete_paths.each do |test_path|
              test_obj.delete(path: test_path)
              expect(test_obj.exists?(path: test_path)).to eq false
            end
          end
        end

        describe '.delete/.children' do
          it 'do not conflict' do
            tgt_paths = %w[foobar foobaz].sort.map { |p| BackupEngine::Pathname.new(p) }

            delete_thread
            collission_count.times do
              expect(test_obj.children(path: 'foo/bar/baz')).to eq(tgt_paths.sort)
            end
          end
        end
      end
    end

    describe 'in-memory store' do
      let(:logger) { Logger.new('/dev/null') }
      let(:test_config) do
        {
          id: 's3_list_cache_spec',
          logger: logger,
          type: 'memory'
        }
      end

      it_behaves_like 'cache behavior'
    end

    describe 'redis store' do
      let(:logger) { Logger.new('/dev/null') }
      let(:test_config) do
        {
          id: "s3_list_cache_spec/#{SecureRandom.hex}",
          logger: logger,
          type: 'redis',
          ttl: 60
        }
      end

      it_behaves_like 'cache behavior'

      # Temporarily disabled as this is a very slow test
      xdescribe 'Performance' do
        # Performance only runs against Redis because the persisten Redis problems allows the huge
        # seed payload to persist between tests

        let(:test_config) do
          {
            id: 's3_list_cache_spec/Performance',
            logger: logger,
            type: 'redis',
            ttl: 36000
          }
        end

        let(:test_obj) do
          described_class.new(**test_config) do |block_test_obj|
            puts ''
            2.times do |level_1_idx|
              100000.times do |level_2_idx|
                puts "[#{Time.now}] TEST: Seeding perf test #{(level_1_idx + 1) * (level_2_idx + 1) / 16000.to_f}% complete" if level_2_idx % 1000 == 0
                2.times do |level_3_idx|
                  2.times do |level_4_idx|
                    2.times do |level_5_idx|
                      path = "#{level_1_idx}/#{level_2_idx}/#{level_3_idx}/#{level_4_idx}/#{level_5_idx}"
                      block_test_obj.add(path: path, date: 100)
                    end
                  end
                end
              end
            end
            puts "[#{Time.now}] TEST: Seeding complete: #{block_test_obj.cache.length} keys"
          end
        end

        describe '.index' do
          it 'generates the index within 120 seconds' do
            start_time = Time.now.to_f
            test_obj.index
            expect(Time.now.to_f - start_time).to be < 120
          end
        end

        describe '.children' do
          before :each do
            # Ensure the index is hot
            test_obj.index
          end

          it 'returns all keys within 10s' do
            start_time = Time.now.to_f
            test_obj.children(path: '', depth: -1)
            expect(Time.now.to_f - start_time).to be < 10
          end

          it 'returns 2nd level keys within 5s' do
            start_time = Time.now.to_f
            test_obj.children(path: '0', depth: -1)
            expect(Time.now.to_f - start_time).to be < 5
          end

          it 'returns 3rd level keys within 0.1s' do
            start_time = Time.now.to_f
            test_obj.children(path: '0/0', depth: -1)
            expect(Time.now.to_f - start_time).to be < 0.1
          end

          it 'returns 4th level keys within 0.05s' do
            start_time = Time.now.to_f
            test_obj.children(path: '0/0/0', depth: -1)
            expect(Time.now.to_f - start_time).to be < 0.05
          end

          it 'returns 5th level keys within 0.01s' do
            start_time = Time.now.to_f
            test_obj.children(path: '0/0/0/0', depth: -1)
            expect(Time.now.to_f - start_time).to be < 0.01
          end
        end
      end
    end
  end
end
