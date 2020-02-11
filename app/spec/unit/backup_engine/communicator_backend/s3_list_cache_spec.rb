require 'securerandom'
require_relative '../../../spec_helper.rb'

require_relative '../../../../lib/backup_engine/communicator_backend/s3_list_cache.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::CommunicatorBackend::S3ListCache do
    shared_examples 'cache behavior' do
      let(:test_obj) { described_class.new(test_config) { |_| nil } }

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
        it 'returns the child list on empty path' do
          test_obj.add(path: 'foo', date: 100)
          test_obj.add(path: 'bar', date: 300)
          test_obj.add(path: 'baz', date: 200)

          expect(test_obj.children(path: '/')).to eq %w[foo bar baz]
        end

        it 'raises exception on unknown key' do
          expect { test_obj.children(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
        end

        it 'returns nested child lists' do
          test_obj.add(path: 'foo/bar/baz/foobar/barbaz', date: 100)
          test_obj.add(path: 'foo/bar/baz/foobaz/barbaz', date: 100)
          test_obj.add(path: 'bar', date: 300)
          test_obj.add(path: 'baz', date: 200)

          expect(test_obj.children(path: 'foo/bar/baz')).to eq %w[foobar foobaz]
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

      describe 'Cache Seeding' do
        let(:seed_values) do
          Hash.new.tap do |h|
            h[Array.new(3) { SecureRandom.hex }.join('/')] = rand(0..1000)
          end
        end

        let(:test_obj) do
          described_class.new(test_config) do |cache_obj|
            # Test: Cache should never seed unless empty
            raise('Attempted to seed non-empty cache') unless cache_obj.cache.empty?

            seed_values.each_pair do |path, date|
              cache_obj.add(path: path, date: date)
            end
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
        end
      end
    end

    describe 'in-memory store' do
      let(:test_config) do
        {
          id: 's3_list_cache_spec',
          type: 'memory',
          ttl: 10
        }
      end

      it_behaves_like 'cache behavior'
    end

    describe 'redis store' do
      let(:test_config) do
        {
          id: "s3_list_cache_spec/#{SecureRandom.hex}",
          type: 'redis',
          ttl: 10
        }
      end

      it_behaves_like 'cache behavior'
    end
  end
end
