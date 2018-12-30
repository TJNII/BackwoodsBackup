require 'base64'
require 'openssl'
require 'pathname'

module BackupEngine
  module Encryption
    module Engines
      # This engine uses asymmetric RSA encryption to encrypt the keys for the blocks
      # which are encrypted using symmetric encryption.
      # Keys is a hash of keys of the form:
      # { "key name" => {public: "pubkey", private: "privkey" }
      # private can be omitted for encryption (backups) and public can be omitted for decryption (restores)
      class ASymmetricRSA
        DEFAULT_SYMMETRIC_ALGORITHM = 'AES-256-CBC'

        def initialize(communicator:, keys:, logger:)
          @communicator = communicator
          @logger = logger

          @keys = {}
          keys.each_pair do |name, rsa_keys|
            # Use the sha256 of the user name as the internal name
            # This is to both avoid naming problems when uploading and to obfuscate the key name
            keys_key = BackupEngine::Checksums::Engines::SHA256.new.block(name)
            raise("Key name sha collission") if @keys.key?(keys_key)
            @keys[keys_key] = rsa_keys.merge(name: name)
          end
        end

        def exists?(path:)
          # Only return true if the payload exists for all keys
          @keys.keys.each do |key_id|
            return false unless @communicator.exists?(path: symmetric_key_path(path, key_id))
          end
          return true
        end

        def encrypt(path:, payload:, metadata:)
          # This does not reuse existing symmetric blocks as it cannot decrypt them
          # Instead it uploads a new symmetric block, and updates all asymmetric keys to point at it
          # Orphaned blocks are intended to be cleaned up by a cleaner tool.
          symmetric_details = symmetric_encrypt(base_path: path, payload: payload, metadata: metadata)
          
          @keys.each_pair do |key_id, key_values|
            raise("No public key for #{key_values[:name]}") if key_values[:public].nil?

            public_key_obj = OpenSSL::PKey::RSA.new(key_values[:public])
            # RSA can't do arbitrary length strings, so only encrypt the key
            encrypted_key = public_key_obj.public_encrypt(symmetric_details[:key])

            @communicator.upload(path: symmetric_key_path(path, key_id),
                                 payload: encrypted_key,
                                 metadata: { 
                                   encryption: { 
                                     algorithm: 'RSA',
                                     target: {
                                       algorithm: symmetric_details[:algorithm],
                                       path: symmetric_details[:path]
                                     }
                                   }
                                 })
          end
        end

        def decrypt(path:)
          @keys.each_pair do |key_id, key_values|
            if key_values[:private].nil?
              @logger.error("No private key for #{key_values[:name]}") 
              next
            end

            # Roll through the keys until we find one we have
            next unless @communicator.exists?(path: symmetric_key_path(path, key_id))

            communicator_payload = @communicator.download(path: symmetric_key_path(path, key_id))
            raise("Algorithm Mismatch: RSA:#{communicator_payload[:metadata][:encryption][:algorithm]}") if communicator_payload[:metadata][:encryption][:algorithm] != 'RSA'

            private_key_obj = OpenSSL::PKey::RSA.new(key_values[:private])
            key = private_key_obj.private_decrypt(communicator_payload[:payload])
            return symmetric_decrypt(key: key, path: communicator_payload[:metadata][:encryption][:target][:path], algorithm: communicator_payload[:metadata][:encryption][:target][:algorithm])
          end

          raise("Unable to decrypt #{path} with any available RSA keys")
        end
          
        private

        def symmetric_key_path(base_path, key_id)
          return base_path.join('asym_keys').join(key_id.to_s).join('sym_key.bin')
        end

        def symmetric_encrypt(base_path:, payload:, metadata:)
          key = OpenSSL::Cipher::Cipher.new(DEFAULT_SYMMETRIC_ALGORITHM).random_key
          key_sha = BackupEngine::Checksums::Engines::SHA256.new.block(key)
          path = base_path.join('asym_blocks').join(key_sha.to_s)

          symmetric_engine = BackupEngine::Encryption::Engines::Symmetric.new(communicator: @communicator, 
                                                                              settings: {
                                                                                key: key,
                                                                                algorithm: DEFAULT_SYMMETRIC_ALGORITHM
                                                                              })
          symmetric_engine.encrypt(path: path, payload: payload, metadata: metadata)
          return { 
            key: Base64.encode64(key),
            algorithm: DEFAULT_SYMMETRIC_ALGORITHM,
            path: path
          }
        end

        def symmetric_decrypt(key:, algorithm:, path:)
          symmetric_engine = BackupEngine::Encryption::Engines::Symmetric.new(communicator: @communicator,
                                                                              settings: {
                                                                                key: Base64.decode64(key),
                                                                                algorithm: algorithm
                                                                              })
          symmetric_engine.decrypt(path: Pathname.new(path))
        end
      end
    end
  end
end
