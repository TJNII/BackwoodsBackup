require 'base64'
require 'openssl'
require 'pathname'

module BackupEngine
  module Encryption
    module Engines
      class Symmetric
        def initialize(communicator:, settings:)
          @communicator = communicator

          %i[algorithm key].each do |required_setting|
            raise("Settings missing required key #{required_setting}") unless settings.key?(required_setting)
          end

          @settings = settings.freeze
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

        private

        def out_path(in_path)
          return in_path.join('sym.bin')
        end
      end
    end
  end
end
