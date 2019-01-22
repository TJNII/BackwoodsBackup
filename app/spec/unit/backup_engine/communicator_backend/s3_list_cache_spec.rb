require_relative '../../../spec_helper.rb'

require_relative '../../../../lib/backup_engine/communicator_backend/s3_list_cache.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::CommunicatorBackend::S3ListCache do
    let(:test_class) { described_class.new }

    describe '[]' do
      it 'converts the path to an array and calls lookup_by_array' do
        expect(test_class).to receive(:lookup_by_array).with(path_array: %w[foo bar baz])
        test_class['foo/bar/baz']
      end

      it 'rasies exception on absolute paths' do
        expect { test_class['/foo/bar/baz'] }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'add' do
      it 'converts the path to an array and calls add_by_array' do
        expect(test_class).to receive(:add_by_array).with(path_array: %w[foo bar baz], date: 'test_date')
        test_class.add(path: 'foo/bar/baz', date: 'test_date')
      end

      it 'rasies exception on absolute paths' do
        expect { test_class.add(path: '/foo/bar/baz', date: 'test_date') }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'add_by_array' do
      it 'adds to the cache' do
        test_class.add_by_array(path_array: %w[foo bar], date: 100)
        test_class.add_by_array(path_array: %w[foo baz], date: 200)
        test_class.add_by_array(path_array: %w[bar baz], date: 300)

        expect(test_class.cache['foo'].cache['bar'].date).to eql(100)
        expect(test_class.cache['foo'].cache['baz'].date).to eql(200)
        expect(test_class.cache['bar'].cache['baz'].date).to eql(300)
      end

      it 'applies the date to all lower keys' do
        test_class.add_by_array(path_array: %w[foo bar baz], date: 100)
        expect(test_class.cache['foo'].cache['bar'].cache['baz'].date).to eql(100)
        expect(test_class.cache['foo'].cache['bar'].date).to eql(100)
        expect(test_class.cache['foo'].date).to eql(100)
      end

      it 'updates lower keys without discarding data' do
        test_class.add_by_array(path_array: %w[foo bar], date: 100)
        test_class.add_by_array(path_array: %w[foo baz], date: 200)
        test_class.add_by_array(path_array: %w[foo], date: 300)

        expect(test_class.cache['foo'].cache['bar'].date).to eql(100)
        expect(test_class.cache['foo'].cache['baz'].date).to eql(200)
        expect(test_class.cache['foo'].date).to eql(300)
      end

      it 'propagates the newest date down' do
        test_class.add_by_array(path_array: %w[foo bar baz], date: 300)
        test_class.add_by_array(path_array: %w[foo bar], date: 200)
        test_class.add_by_array(path_array: %w[foo], date: 100)

        expect(test_class.cache['foo'].cache['bar'].cache['baz'].date).to eql(300)
        expect(test_class.cache['foo'].cache['bar'].date).to eql(300)
        expect(test_class.cache['foo'].date).to eql(300)
      end
    end

    describe 'cache' do
      it 'is immutable' do
        expect { test_class.cache['foo'] = nil }.to raise_exception(FrozenError)
      end
    end

    describe 'children' do
      it 'converts the path to an array and calls children_by_array' do
        expect(test_class).to receive(:children_by_array).with(path_array: %w[foo bar baz])
        test_class.children(path: 'foo/bar/baz')
      end

      it 'rasies exception on absolute paths' do
        expect { test_class.children(path: '/foo/bar/baz') }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'children_by_array' do
      it 'raises exception on incomplete cache' do
        test_class.add_by_array(path_array: %w[foo], date: 100)
        expect { test_class.children_by_array(path_array: %w[foo]) }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end

      it 'returns the child list on empty list' do
        test_class.add_by_array(path_array: %w[foo], date: 100)
        test_class.add_by_array(path_array: %w[bar], date: 300)
        test_class.add_by_array(path_array: %w[baz], date: 200)
        test_class.mark_complete_by_array(path_array: [])

        expect(test_class.children_by_array(path_array: [])).to eq %w[foo bar baz]
      end

      it 'raises exception unknown key' do
        test_class.mark_complete_by_array(path_array: [])
        expect { test_class.children_by_array(path_array: %w[unknown key]) }.to raise_exception(Errno::ENOENT)
      end

      it 'returns nested child lists' do
        test_class.add_by_array(path_array: %w[foo bar baz foobar], date: 100)
        test_class.add_by_array(path_array: %w[foo bar baz foobaz], date: 100)
        test_class.add_by_array(path_array: %w[bar], date: 300)
        test_class.add_by_array(path_array: %w[baz], date: 200)
        test_class.mark_complete_by_array(path_array: [])

        expect(test_class.children_by_array(path_array: %w[foo bar baz])).to eq %w[foobar foobaz]
      end
    end

    describe 'complete?' do
      it 'defaults to false' do
        expect(test_class.complete?).to be false
      end

      it 'returns self complete flag on no path' do
        test_class.mark_complete_by_array(path_array: [])
        expect(test_class.complete?).to be true
      end

      it 'converts the path to an array and calls complete_by_array' do
        expect(test_class).to receive(:complete_by_array?).with(path_array: %w[foo bar baz])
        test_class.complete?(path: 'foo/bar/baz')
      end

      it 'rasies exception on absolute paths' do
        expect { test_class.complete?(path: '/foo/bar/baz') }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'complete_by_array?' do
      it 'defaults to false' do
        expect(test_class.complete_by_array?(path_array: [])).to be false
      end

      it 'returns false on unknown key' do
        test_class.mark_complete_by_array(path_array: [])
        expect(test_class.complete_by_array?(path_array: [])).to be true
        expect(test_class.complete_by_array?(path_array: %w[unknown key])).to be false
      end

      it 'returns true when marked complete' do
        test_class.mark_complete_by_array(path_array: [])
        expect(test_class.complete_by_array?(path_array: [])).to be true
      end

      it 'returns complete for child caches' do
        test_class.add_by_array(path_array: %w[foo bar], date: 100)
        test_class.mark_complete_by_array(path_array: %w[foo bar])

        expect(test_class.complete_by_array?(path_array: [])).to be false
        expect(test_class.complete_by_array?(path_array: %w[foo])).to be false
        expect(test_class.complete_by_array?(path_array: %w[foo bar])).to be true
      end
    end

    describe 'delete' do
      it 'converts the path to an array and calls delete_by_array' do
        expect(test_class).to receive(:delete_by_array).with(path_array: %w[foo bar baz])
        test_class.delete(path: 'foo/bar/baz')
      end

      it 'rasies exception on absolute paths' do
        expect { test_class.delete(path: '/foo/bar/baz') }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'delete_by_array' do
      it 'empties the cache on empty list' do
        test_class.add_by_array(path_array: %w[foo bar baz foobar], date: 100)
        test_class.delete_by_array(path_array: [])
        expect(test_class.cache).to be_empty
      end

      it 'raises exception unknown key' do
        expect { test_class.delete_by_array(path_array: %w[unknown key]) }.to raise_exception(Errno::ENOENT)
      end

      it 'recursively deletes child lists and empty parents' do
        test_class.add_by_array(path_array: %w[foo bar baz foobar], date: 100)
        test_class.add_by_array(path_array: %w[foo baz foobar], date: 200)

        test_class.delete_by_array(path_array: %w[foo bar baz])
        expect(test_class.cache['foo'].cache.keys).to eql %w[baz]
      end
    end

    describe 'exists?' do
      it 'converts the path to an array and calls exists_by_array?' do
        expect(test_class).to receive(:exists_by_array?).with(path_array: %w[foo bar baz])
        test_class.exists?(path: 'foo/bar/baz')
      end

      it 'rasies exception on absolute paths' do
        expect { test_class.exists?(path: '/foo/bar/baz') }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'exists_by_array?' do
      it 'returns true on empty list' do
        expect(test_class.exists_by_array?(path_array: [])).to be true
      end

      it 'returns false on unknown key' do
        expect(test_class.exists_by_array?(path_array: %w[unknown key])).to be false
      end

      it 'returns true for known children' do
        test_class.add_by_array(path_array: %w[foo bar], date: 100)
        test_class.add_by_array(path_array: %w[foo baz], date: 200)
        test_class.add_by_array(path_array: %w[bar baz], date: 300)

        expect(test_class.exists_by_array?(path_array: %w[foo bar])).to be true
        expect(test_class.exists_by_array?(path_array: %w[foo baz])).to be true
        expect(test_class.exists_by_array?(path_array: %w[bar baz])).to be true
      end
    end

    describe 'lookup_by_array' do
      it 'returns the parent date on empty list' do
        raise('Test Error: test_class date not in expected state') unless test_class.date == 0

        expect(test_class.lookup_by_array(path_array: [])).to eq 0
      end

      it 'returns the parent date on unknown key' do
        raise('Test Error: test_class date not in expected state') unless test_class.date == 0

        expect(test_class.lookup_by_array(path_array: %w[unknown key])).to eq 0
      end

      it 'returns child dates' do
        test_class.add_by_array(path_array: %w[foo bar], date: 100)
        test_class.add_by_array(path_array: %w[foo baz], date: 200)
        test_class.add_by_array(path_array: %w[bar baz], date: 300)

        expect(test_class.lookup_by_array(path_array: %w[foo bar])).to eql(100)
        expect(test_class.lookup_by_array(path_array: %w[foo baz])).to eql(200)
        expect(test_class.lookup_by_array(path_array: %w[bar baz])).to eql(300)
      end
    end

    describe 'mark_complete' do
      it 'converts the path to an array and calls mark_complete_by_array' do
        expect(test_class).to receive(:mark_complete_by_array).with(path_array: %w[foo bar baz])
        test_class.mark_complete(path: 'foo/bar/baz')
      end

      it 'rasies exception on absolute paths' do
        expect { test_class.mark_complete(path: '/foo/bar/baz') }.to raise_exception(BackupEngine::CommunicatorBackend::S3ListCacheError)
      end
    end

    describe 'mark_complete_by_array' do
      it 'marks all self and all child caches complete on empty array' do
        test_class.add_by_array(path_array: %w[foo bar baz], date: 100)
        test_class.mark_complete_by_array(path_array: [])

        expect(test_class.complete?).to be true
        expect(test_class.cache['foo'].complete?).to be true
        expect(test_class.cache['foo'].cache['bar'].complete?).to be true
      end

      it 'no-ops on unknown key' do
        test_class.mark_complete_by_array(path_array: %w[unknown key])
        expect(test_class.complete?).to be false
      end

      it 'recursively marks complete child lists but not parents' do
        test_class.add_by_array(path_array: %w[foo bar baz foobar], date: 100)
        test_class.add_by_array(path_array: %w[foo bar foobar], date: 200)
        test_class.add_by_array(path_array: %w[foo baz foobar], date: 300)

        test_class.mark_complete_by_array(path_array: %w[foo bar])
        expect(test_class.complete?).to be false
        expect(test_class.cache['foo'].complete?).to be false
        expect(test_class.cache['foo'].cache['baz'].complete?).to be false
        expect(test_class.cache['foo'].cache['baz'].cache['foobar'].complete?).to be false

        expect(test_class.cache['foo'].cache['bar'].complete?).to be true
        expect(test_class.cache['foo'].cache['bar'].cache['baz'].complete?).to be true
        expect(test_class.cache['foo'].cache['bar'].cache['baz'].cache['foobar'].complete?).to be true
        expect(test_class.cache['foo'].cache['bar'].cache['foobar'].complete?).to be true
      end
    end
  end
end
