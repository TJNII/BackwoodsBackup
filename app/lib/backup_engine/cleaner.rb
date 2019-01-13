require_relative('block_encoder.rb')
require_relative('manifest.rb')

module BackupEngine
  module Cleaner
    def self.clean(encryption_engine:, logger:, min_block_age:, min_manifest_age:, min_set_manifests:)
      _ensure_blocks_consistent(communicator: encryption_engine.communicator, logger: logger)
      _ensure_manifests_consistent(communicator: encryption_engine.communicator, logger: logger)

      used_blocks = _clean_manifests_and_return_blocks(encryption_engine: encryption_engine, logger: logger, min_manifest_age: min_manifest_age, min_set_manifests: min_set_manifests)
      _remove_unused_blocks(communicator: encryption_engine.communicator, logger: logger, used_blocks: used_blocks, min_block_age: min_block_age)

      _clean_empty_manifest_directories(communicator: encryption_engine.communicator, logger: logger)
    end

    def self._clean_empty_manifest_directories(communicator:, logger:)
      BackupEngine::Manifest.list_manifest_backups(communicator: communicator).each do |path|
        if communicator.list(path: path).empty?
          logger.debug("Removing empty manifest backup directory #{path}")
          communicator.delete(path: path)
        end
      end

      BackupEngine::Manifest.list_manifest_sets(communicator: communicator).each do |path|
        if communicator.list(path: path).empty?
          logger.debug("Removing empty manifest set directory #{path}")
          communicator.delete(path: path)
        end
      end

      BackupEngine::Manifest.list_manifest_hosts(communicator: communicator).each do |path|
        if communicator.list(path: path).empty?
          logger.debug("Removing empty manifest host directory #{path}")
          communicator.delete(path: path)
        end
      end
    end

    # Note: This loads all the manifests
    def self._clean_manifests_and_return_blocks(encryption_engine:, logger:, min_manifest_age:, min_set_manifests:)
      used_blocks = []
      BackupEngine::Manifest.list_manifest_sets(communicator: encryption_engine.communicator).each do |set_path|
        target_manifests = {}
        encryption_engine.communicator.list(path: set_path).each do |manifest_path|
          age = Time.new - encryption_engine.communicator.date(path: manifest_path)
          if age < min_manifest_age
            used_blocks += _get_manifest_blocks(path: manifest_path, encryption_engine: encryption_engine, logger: logger)
          else
            target_manifests[manifest_path] = age
          end
        end

        target_manifests.keys.sort! { |k| target_manifests[k] }.reverse.each_with_index do |path, idx|
          if idx >= min_set_manifests
            logger.info("Removing old manifest #{path} (#{target_manifests[path]} old)")
            encryption_engine.communicator.delete(path: path)
          else
            used_blocks += _get_manifest_blocks(path: path, encryption_engine: encryption_engine, logger: logger)
          end
        end
      end

      return used_blocks
    end

    def self._ensure_blocks_consistent(communicator:, logger:)
      BackupEngine::BlockEncoder.list_blocks(communicator: communicator).each do |block_path|
        _ensure_path_consistent(path: block_path, communicator: communicator, logger: logger)
      end
    end

    def self._ensure_manifests_consistent(communicator:, logger:)
      BackupEngine::Manifest.list_manifest_backups(communicator: communicator).each do |manifest_path|
        _ensure_path_consistent(path: manifest_path, communicator: communicator, logger: logger)
      end
    end

    def self._ensure_path_consistent(path:, communicator:, logger:)
      block_types = communicator.list(path: path).map(&:basename)
      if block_types.empty?
        logger.error("No block data in path #{path}")
        communicator.delete(path: path)
        return
      end

      @logger.warn("Multiple encryption methods in use for block #{path}") if block_types.length > 1
      block_types.map(&:to_s).each do |block_type|
        # TODO: Better handling of unneeded settings for these operations
        encryption_engine = if block_type == 'ASymmetricRSA'
                              BackupEngine::Encryption::Engines::ASymmetricRSA.new(communicator: communicator, keys: { dummykey: {} }, logger: logger)
                            elsif block_type == 'Symmetric'
                              BackupEngine::Encryption::Engines::Symmetric.new(communicator: communicator, settings: { algorithm: nil, key: nil }, logger: logger)
                            else
                              raise("Unknown encryption engine #{block_type} for path #{block_path}")
                            end

        encryption_engine.ensure_consistent(path: path)
      end
    end

    # TODO: This knows too much about the format
    def self._get_manifest_blocks(path:, encryption_engine:, logger:)
      used_blocks = []
      manifest = BackupEngine::Manifest.download(path: path, encryption_engine: encryption_engine)
      manifest.manifest.values.each do |metadata|
        next unless metadata.type == 'file'

        metadata.block_map.each do |block_metadata|
          if encryption_engine.communicator.exists?(path: block_metadata['path'])
            used_blocks.push(block_metadata['path'])
          else
            logger.error("Manifest #{path} incomplete: Block #{block_metadata['path']} missing!")
          end
        end
      end

      return used_blocks
    end

    def self._remove_unused_blocks(communicator:, logger:, used_blocks:, min_block_age:)
      BackupEngine::BlockEncoder.list_blocks(communicator: communicator).each do |block_path|
        next if used_blocks.include? block_path.to_s

        block_age = Time.new - communicator.date(path: block_path)
        if block_age <= min_block_age
          logger.debug("Block #{block_path} (#{block_age} old) unused but below minimum age")
        else
          logger.info("Removing unreferenced block #{block_path} (#{block_age} old)")
          communicator.delete(path: block_path)
        end
      end
    end
  end
end
