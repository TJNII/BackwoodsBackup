require_relative '../../../spec_helper.rb'

require_relative '../../../../lib/backup_engine/communicator_backend/s3_list_cache.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::CommunicatorBackend::S3ListCache do
    let(:test_class) { described_class.new }

    describe 'add' do
      it 'adds to the cache' do
        test_class.add(path: 'foo/bar', date: 100)
        test_class.add(path: 'foo/baz', date: 200)
        test_class.add(path: 'bar/baz', date: 300)

        expect(test_class.cache['/foo/bar']).to eql(100)
        expect(test_class.cache['/foo/baz']).to eql(200)
        expect(test_class.cache['/bar/baz']).to eql(300)
      end

      it 'applies the date to all lower keys' do
        test_class.add(path: 'foo/bar/baz', date: 100)
        expect(test_class.cache['/foo/bar/baz']).to eql(100)
        expect(test_class.cache['/foo/bar']).to eql(100)
        expect(test_class.cache['/foo']).to eql(100)
      end

      it 'updates lower keys without discarding data' do
        test_class.add(path: 'foo/bar', date: 100)
        test_class.add(path: 'foo/baz', date: 200)
        test_class.add(path: 'foo', date: 300)

        expect(test_class.cache['/foo/bar']).to eql(100)
        expect(test_class.cache['/foo/baz']).to eql(200)
        expect(test_class.cache['/foo']).to eql(300)
      end

      it 'propagates the newest date down' do
        test_class.add(path: 'foo/bar/baz', date: 300)
        test_class.add(path: 'foo/bar', date: 200)
        test_class.add(path: 'foo', date: 100)

        expect(test_class.cache['/foo/bar/baz']).to eql(300)
        expect(test_class.cache['/foo/bar']).to eql(300)
        expect(test_class.cache['/foo']).to eql(300)
      end
    end

    describe 'cache' do
      it 'is immutable' do
        expect { test_class.cache['foo'] = nil }.to raise_exception(FrozenError)
      end
    end

    describe 'children' do
      it 'returns the child list on empty path' do
        test_class.add(path: 'foo', date: 100)
        test_class.add(path: 'bar', date: 300)
        test_class.add(path: 'baz', date: 200)

        expect(test_class.children(path: '/')).to eq %w[foo bar baz]
      end

      it 'raises exception on unknown key' do
        expect { test_class.children(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
      end

      it 'returns nested child lists' do
        test_class.add(path: 'foo/bar/baz/foobar/barbaz', date: 100)
        test_class.add(path: 'foo/bar/baz/foobaz/barbaz', date: 100)
        test_class.add(path: 'bar', date: 300)
        test_class.add(path: 'baz', date: 200)

        expect(test_class.children(path: 'foo/bar/baz')).to eq %w[foobar foobaz]
      end
    end

    describe '.date' do
      it 'raises exception unknown key' do
        expect { test_class.date(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
      end

      it 'returns child dates' do
        test_class.add(path: 'foo/bar', date: 100)
        test_class.add(path: 'foo/baz', date: 200)
        test_class.add(path: 'bar/baz', date: 300)

        expect(test_class.date(path: 'foo/bar')).to eql(100)
        expect(test_class.date(path: 'foo/baz')).to eql(200)
        expect(test_class.date(path: 'bar/baz')).to eql(300)
      end
    end

    describe 'delete' do
      it 'empties the cache on empty path' do
        test_class.add(path: 'foo/bar/baz/foobar', date: 100)
        test_class.delete(path: '')
        expect(test_class.cache).to be_empty
      end

      it 'raises exception unknown key' do
        expect { test_class.delete(path: 'unknown/key') }.to raise_exception(Errno::ENOENT)
      end

      it 'recursively deletes child lists and empty parents' do
        test_class.add(path: 'foo/bar/baz/foobar', date: 100)
        test_class.add(path: 'foo/baz/foobar', date: 200)

        test_class.delete(path: 'foo/bar/baz')
        expect(test_class.cache.keys.sort).to eql %w[/ /foo /foo/baz /foo/baz/foobar]
      end
    end

    describe 'exists?' do
      it 'returns false on unknown key' do
        expect(test_class.exists?(path: 'unknown/key')).to be false
      end

      it 'returns true for known children' do
        test_class.add(path: 'foo/bar', date: 100)
        test_class.add(path: 'foo/baz', date: 200)
        test_class.add(path: 'bar/baz', date: 300)

        expect(test_class.exists?(path: 'foo/bar')).to be true
        expect(test_class.exists?(path: 'foo/baz')).to be true
        expect(test_class.exists?(path: 'bar/baz')).to be true
      end
    end
  end
end
