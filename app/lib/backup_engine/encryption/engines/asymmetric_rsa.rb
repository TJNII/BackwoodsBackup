require 'base64'
require 'openssl'
require 'pathname'
require 'securerandom'

module BackupEngine
  module Encryption
    module Engines
      # This engine uses asymmetric RSA encryption to encrypt the keys for the blocks
      # which are encrypted using symmetric encryption.
      # Keys is a hash of keys of the form:
      # { "key name" => {public: "pubkey", private: "privkey" }
      # private can be omitted for encryption (backups) and public can be omitted for decryption (restores)
      class ASymmetricRSA
        DEFAULT_SYMMETRIC_ALGORITHM = 'AES-256-CBC'.freeze

        BLOCKS_DIR = Pathname.new('ASymmetricRSA').join('asym_blocks').freeze
        KEYS_DIR = Pathname.new('ASymmetricRSA').join('asym_keys').freeze

        attr_reader :communicator

        def initialize(communicator:, logger:, keys: {})
          @communicator = communicator
          @logger = logger
          @user_keys = keys.freeze
        end

        def decrypt(path:)
          keys.each_pair do |key_id, key_values|
            if key_values[:private].nil?
              @logger.error("No private key for #{key_values[:name]}")
              next
            end

            # Roll through the keys until we find one we have
            next unless @communicator.exists?(path: symmetric_key_path(base_path: path, key_id: key_id))

            communicator_payload = @communicator.download(path: symmetric_key_path(base_path: path, key_id: key_id))
            raise("Algorithm Mismatch: RSA:#{communicator_payload[:metadata][:encryption][:algorithm]}") if communicator_payload[:metadata][:encryption][:algorithm] != 'RSA'

            private_key_obj = OpenSSL::PKey::RSA.new(key_values[:private])
            key = private_key_obj.private_decrypt(communicator_payload[:payload])
            return symmetric_decrypt(key: key, path: communicator_payload[:metadata][:encryption][:target][:path], algorithm: communicator_payload[:metadata][:encryption][:target][:algorithm])
          end

          raise("Unable to decrypt #{path} with any available RSA keys")
        end

        def delete(path:)
          @communicator.delete(path: path)
        end

        def ensure_consistent(path:, verify_block_checksum:)
          # Iterate over all the keys in path, and ensure they have corresponding blocks
          # NOTE: This downloads all the key files
          unless @communicator.exists?(path: path.join(KEYS_DIR))
            @logger.error("Asymmetric keys directory missing for #{path}")
            delete(path: path)
            return false
          end

          key_paths = @communicator.list(path: path.join(KEYS_DIR))
          if key_paths.empty?
            @logger.warn("No keys for #{path}")
            delete(path: path)
            return false
          end

          symmetric_engine = BackupEngine::Encryption::Engines::Symmetric.new(communicator: @communicator, logger: @logger)
          known_block_paths = []
          key_paths.each do |key_path|
            unless @communicator.exists?(path: key_path.join('sym_key.bin'))
              @logger.error("Symmetric key file missing for #{key_path}")
              @communicator.delete(path: key_path)
              next
            end

            key_payload = @communicator.download(path: key_path.join('sym_key.bin'), verify_payload_checksum: verify_block_checksum)
            if symmetric_engine.ensure_consistent(path: Pathname.new(key_payload[:metadata][:encryption][:target][:path]), verify_block_checksum: verify_block_checksum)
              @logger.debug("Symmetric block exists for #{key_path}")
              known_block_paths.push(key_payload[:metadata][:encryption][:target][:path])
            else
              @communicator.delete(path: key_path)
            end
          rescue BackupEngine::CommunicatorBackend::Encoder::VerifyError => e
            @logger.error("Corrupt key: #{key_path}: #{e}")
            @communicator.delete(path: key_path)
          end

          known_block_paths.uniq!
          if known_block_paths.empty?
            @logger.warn("No blocks for #{path}")
            delete(path: path)
            return false
          end

          # Ensure the blocks are accessible
          @communicator.list(path: path.join(BLOCKS_DIR)).each do |block_path|
            next if known_block_paths.include?(block_path.to_s)

            @logger.info("Remove unreferenced symmetric block #{block_path}")
            @communicator.delete(path: block_path)
          end

          return true
        end

        def exists?(path:)
          # Only return true if the payload exists for all keys
          # Note this is lazy and DOES NOT CHECK THAT THE BLOCK EXISTS.
          # This is for speed/cost/bandwidth: the keyfile would need to be downloaded to get the block ID to check that it exists
          # Consistency is intended to be enforced by the cleaner script
          keys.keys.each do |key_id|
            return false unless @communicator.exists?(path: symmetric_key_path(base_path: path, key_id: key_id))
          end
          return true
        end

        def encrypt(path:, payload:, metadata:)
          # This does not reuse existing symmetric blocks as it cannot decrypt them
          # Instead it uploads a new symmetric block, and updates all asymmetric keys to point at it
          # Orphaned blocks are intended to be cleaned up by a cleaner tool.
          symmetric_details = symmetric_encrypt(base_path: path, payload: payload, metadata: metadata)

          keys.each_pair do |key_id, key_values|
            raise("No public key for #{key_values[:name]}") if key_values[:public].nil?

            public_key_obj = OpenSSL::PKey::RSA.new(key_values[:public])
            # RSA can't do arbitrary length strings, so only encrypt the key
            encrypted_key = public_key_obj.public_encrypt(symmetric_details[:key])

            @communicator.upload(path: symmetric_key_path(base_path: path, key_id: key_id),
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

        # This is an intermediary step to process and check the keys only when they are needed.
        # It processes them into the needed internal format and saves them in a "verified" variable
        # that can be used by the methods that need them.
        # The spirit of this method is to allow the keys to be optional in the constructor as
        # the encrypt/decrypt methods require the settings but the cleaner methods do not
        # (and the settings are unknown to the code simply performing a clean.)
        def keys
          return @keys unless @keys.nil?

          @keys = {}
          @user_keys.each_pair do |name, rsa_keys|
            # Use the sha256 of the user name as the internal name
            # This is to both avoid naming problems when uploading and to obfuscate the key name
            keys_key = BackupEngine::Checksums::Engines::SHA256.new.block(name.to_s)
            raise('Key name sha collission') if @keys.key?(keys_key)

            @keys[keys_key] = rsa_keys.merge(name: name)
          end

          raise('No encryption keys') if @keys.empty?

          return @keys
        end

        private

        def block_path(base_path:, key_id:)
          return base_path.join(BLOCKS_DIR).join(key_id.to_s)
        end

        def symmetric_key_path(base_path:, key_id:)
          return base_path.join(KEYS_DIR).join(key_id.to_s).join('sym_key.bin')
        end

        def symmetric_encrypt(base_path:, payload:, metadata:)
          key = OpenSSL::Cipher.new(DEFAULT_SYMMETRIC_ALGORITHM).random_key
          key_id = SecureRandom.uuid

          symmetric_engine = BackupEngine::Encryption::Engines::Symmetric.new(communicator: @communicator,
                                                                              settings: {
                                                                                key: key,
                                                                                algorithm: DEFAULT_SYMMETRIC_ALGORITHM
                                                                              },
                                                                              logger: @logger)
          symmetric_engine.encrypt(path: block_path(base_path: base_path, key_id: key_id), payload: payload, metadata: metadata)
          return {
            key: Base64.encode64(key),
            algorithm: DEFAULT_SYMMETRIC_ALGORITHM,
            path: block_path(base_path: base_path, key_id: key_id)
          }
        end

        def symmetric_decrypt(key:, algorithm:, path:)
          symmetric_engine = BackupEngine::Encryption::Engines::Symmetric.new(communicator: @communicator,
                                                                              settings: {
                                                                                key: Base64.decode64(key),
                                                                                algorithm: algorithm
                                                                              },
                                                                              logger: @logger)
          symmetric_engine.decrypt(path: Pathname.new(path))
        end
      end
    end
  end
end
