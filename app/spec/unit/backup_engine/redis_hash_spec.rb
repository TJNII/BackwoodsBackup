require 'securerandom'
require_relative '../../spec_helper.rb'

require_relative '../../../lib/backup_engine/redis_hash.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::RedisHash do
    let(:test_redis) { Redis.new }
    let(:test_redis_path) { "BackupEngineTest/Unit/RedisHash/#{SecureRandom.hex}" }
    let(:exemplar) { Hash.new }
    let(:test_ttl) { 10 }
    let(:test_obj) do
      described_class.new(redis_communicator: test_redis,
                          redis_path: test_redis_path,
                          ttl: test_ttl)
    end

    before :each do
      10.times do
        key = SecureRandom.hex
        value = SecureRandom.hex

        exemplar[key] = value
        test_obj[key] = value
      end
    end

    describe '[]' do
      describe 'without a default block' do
        it 'returns the stored values' do
          exemplar.keys.each do |key|
            expect(test_obj[key]).to eq(exemplar[key])
          end
        end

        it 'returns nil for unknown values' do
          expect(test_obj[SecureRandom.hex]).to eq nil
        end
      end

      describe 'with a default block' do
        let(:dynamic_values) { Hash.new { |h, k| h[k] = SecureRandom.hex } }
        let(:test_obj) do
          described_class.new(redis_communicator: test_redis,
                              redis_path: test_redis_path,
                              ttl: test_ttl) do |h, k|
            h[k] = dynamic_values[k]
          end
        end

        it 'returns the stored values' do
          exemplar.keys.each do |key|
            expect(test_obj[key]).to eq(exemplar[key])
          end
        end

        it 'returns the default block value on unknown keys' do
          key = SecureRandom.hex
          expect(test_obj[key]).to eq(dynamic_values[key])
        end

        it 'allows saving within the default block' do
          key = SecureRandom.hex
          test_obj[key]
          expect(test_obj[key]).to eq(dynamic_values[key])
        end

        it 'sets the object ttl when creating a new Redis hash on unknown keys' do
          other_test_obj = described_class.new(redis_communicator: test_redis,
                                               redis_path: "BackupEngineTest/Unit/RedisHash/#{SecureRandom.hex}",
                                               ttl: test_ttl) do |h, k|
            h[k] = dynamic_values[k]
          end

          expect(other_test_obj.ttl).to be < 0
          other_test_obj[SecureRandom.hex]
          expect(other_test_obj.ttl).to eq(test_ttl)
        end
      end
    end

    describe '[]=' do
      it 'sets values' do
        key = SecureRandom.hex
        value = SecureRandom.hex
        test_obj[key] = value
        expect(test_obj[key]).to eq(value)
      end

      it 'ensures the TTL is set' do
        other_test_obj = described_class.new(redis_communicator: test_redis,
                                             redis_path: "BackupEngineTest/Unit/RedisHash/#{SecureRandom.hex}",
                                             ttl: test_ttl)

        expect(other_test_obj.ttl).to be < 0
        other_test_obj[SecureRandom.hex] = SecureRandom.hex
        expect(other_test_obj.ttl).to eq test_ttl
      end

      it 'does not overwrite existing TTLs' do
        key = SecureRandom.hex
        value = SecureRandom.hex
        test_obj[key] = value
        expect(test_obj.ttl).to eq test_ttl
        sleep(1)
        expect(test_obj.ttl).to be > 0
        expect(test_obj.ttl).to be < test_ttl
        test_obj[key] = value
        expect(test_obj.ttl).to be > 0
        expect(test_obj.ttl).to be < test_ttl
      end

      it 'Resets TTLs over specified TTL' do
        other_test_obj = described_class.new(redis_communicator: test_redis,
                                             redis_path: test_redis_path,
                                             ttl: test_ttl - 5)

        key = SecureRandom.hex
        value = SecureRandom.hex
        test_obj[key] = value
        expect(test_obj.ttl).to eq test_ttl
        other_test_obj[key] = value
        expect(other_test_obj.ttl).to eq(test_ttl - 5)
      end
    end

    describe '.clear' do
      it 'empties the hash' do
        expect(test_obj.to_h).not_to be_empty
        expect(test_obj.clear).to eq test_obj
        expect(test_obj.to_h).to be_empty
      end
    end

    describe '.delete' do
      it 'deletes keys from the hash' do
        key = exemplar.keys[0]
        test_obj.delete(key)
        expect(test_obj[key]).to eq nil
      end
    end

    describe '.delete_if' do
      it 'yields all key/value pairs to the block' do
        expect { |b| test_obj.delete_if(&b) }.to yield_successive_args(*exemplar.to_a)
      end

      it 'deletes keys from the hash when the block is truthy' do
        responses = { exemplar.keys[0] => true,
                      exemplar.keys[1] => false,
                      exemplar.keys[2] => nil,
                      exemplar.keys[3] => :buttons }

        test_obj.delete_if { |key, _| responses[key] }
        exemplar.keys.each do |key|
          expect(test_obj.key?(key)).to eq !responses[key]
        end
      end
    end

    describe '.empty?' do
      it 'returns false when the hash contains data' do
        expect(test_obj.empty?).to eq false
      end

      it 'returns true when the hash is empty' do
        other_test_obj = described_class.new(redis_communicator: test_redis,
                                             redis_path: "BackupEngineTest/Unit/RedisHash/#{SecureRandom.hex}",
                                             ttl: test_ttl)

        expect(other_test_obj.empty?).to eq true
      end
    end

    describe '.fetch' do
      describe 'with one argument' do
        it 'returns the stored values' do
          exemplar.keys.each do |key|
            expect(test_obj.fetch(key)).to eq(exemplar[key])
          end
        end

        it 'raises KeyError for unknown values' do
          expect { test_obj.fetch(SecureRandom.hex) }.to raise_exception(KeyError)
        end
      end

      describe 'with two arguments' do
        it 'returns the stored values' do
          exemplar.keys.each do |key|
            expect(test_obj.fetch(key, :default)).to eq(exemplar[key])
          end
        end

        it 'returns the second argument for unknown values' do
          expect(test_obj.fetch(SecureRandom.hex, :default)).to eq :default
        end
      end
    end

    describe '.key?' do
      it 'returns true for known keys' do
        expect(test_obj.key?(exemplar.keys[0])).to eq true
      end

      it 'returns falsefor unknown keys' do
        expect(test_obj.key?(SecureRandom.hex)).to eq false
      end
    end

    describe '.keys' do
      it 'behaves like Hash #keys' do
        expect(test_obj.keys).to eq(exemplar.keys)
      end
    end

    describe '.length' do
      it 'returns the hash length' do
        expect(test_obj.length).to eq(exemplar.length)
      end
    end

    describe '.merge!' do
      let(:other_values) { Array.new(10) { |_| [SecureRandom.hex, SecureRandom.hex] }.to_h.freeze }

      it 'sets values' do
        expect(test_obj.merge!(other_values)).to eq test_obj
        expect(test_obj.to_h).to eq(exemplar.merge(other_values))
      end

      it 'ensures the TTL is set' do
        other_test_obj = described_class.new(redis_communicator: test_redis,
                                             redis_path: "BackupEngineTest/Unit/RedisHash/#{SecureRandom.hex}",
                                             ttl: test_ttl)

        expect(other_test_obj.ttl).to be < 0
        other_test_obj.merge!(other_values)
        expect(other_test_obj.ttl).to eq test_ttl
      end

      it 'does not overwrite existing TTLs' do
        test_obj.merge!(other_values)
        expect(test_obj.ttl).to eq test_ttl
        sleep(1)
        expect(test_obj.ttl).to be > 0
        expect(test_obj.ttl).to be < test_ttl
        test_obj.merge!(other_values)
        expect(test_obj.ttl).to be > 0
        expect(test_obj.ttl).to be < test_ttl
      end

      it 'Resets TTLs over specified TTL' do
        other_test_obj = described_class.new(redis_communicator: test_redis,
                                             redis_path: test_redis_path,
                                             ttl: test_ttl - 5)

        key = SecureRandom.hex
        value = SecureRandom.hex
        test_obj[key] = value
        expect(test_obj.ttl).to eq test_ttl
        other_test_obj[key] = value
        expect(other_test_obj.ttl).to eq(test_ttl - 5)
      end
    end

    describe '.ttl' do
      it 'returns the TTL remaining' do
        expect(test_obj.ttl).to eq(test_ttl)
      end
    end

    describe '.to_h' do
      it 'returns the hash as a Hash' do
        expect(test_obj.to_h).to eq(exemplar)
      end
    end

    describe '.values' do
      it 'behaves like Hash #values' do
        expect(test_obj.values).to eq(exemplar.values)
      end
    end
  end
end
