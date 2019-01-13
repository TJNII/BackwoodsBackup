require 'base64'
require 'openssl'
require 'pathname'

module BackupEngine
  module Encryption
    module Engines
      class Symmetric
        attr_reader :communicator

        def initialize(communicator:, settings:, logger:)
          @communicator = communicator
          @logger = logger

          %i[algorithm key].each do |required_setting|
            raise("Settings missing required key #{required_setting}") unless settings.key?(required_setting)
          end

          @settings = settings.freeze
        end

        def decrypt(path:)
          communicator_payload = @communicator.download(path: out_path(path))

          raise("Algorithm Mismatch: #{@settings[:algorithm]}:#{communicator_payload[:metadata][:encryption][:algorithm]}") if @settings[:algorithm] != communicator_payload[:metadata][:encryption][:algorithm]

          engine = OpenSSL::Cipher.new(@settings[:algorithm])
          engine.decrypt # Sets encryption mode
          engine.key = @settings[:key]
          engine.iv = Base64.decode64(communicator_payload[:metadata][:encryption][:iv])

          payload = engine.update(communicator_payload[:payload])
          payload << engine.final

          return { metadata: communicator_payload[:metadata], payload: payload }
        end

        def delete(path:)
          @communicator.delete(path: path)
        end

        def ensure_consistent(path:)
          return true if exists?(path: path)

          @logger.warn("No symmetric block data for #{path}")
          delete(path: path)
          return false
        end

        def exists?(path:)
          @communicator.exists?(path: out_path(path))
        end

        def encrypt(path:, payload:, metadata:)
          raise('Encryption metadata key is reserved') if metadata.key?(:encryption)

          iv = OpenSSL::Cipher.new(@settings[:algorithm]).random_iv
          engine = OpenSSL::Cipher.new(@settings[:algorithm])
          engine.encrypt # Sets encryption mode
          engine.key = @settings[:key]
          engine.iv = iv

          cipher = engine.update(payload)
          cipher << engine.final

          @communicator.upload(path: out_path(path),
                               metadata: metadata.merge(encryption: { algorithm: @settings[:algorithm], iv: Base64.encode64(iv) }),
                               payload: cipher)
        end

        private

        def out_path(in_path)
          return in_path.join('Symmetric').join('sym.bin')
        end
      end
    end
  end
end
