require 'zlib'

module BackupEngine
  module Compression
    module Engines
      class Zlib
        def compress(data)
          raise 'Nil data' if data.nil?

          BackupEngine::Compression::Result.new(payload: ::Zlib::Deflate.deflate(data), algorithm: 'zlib', encoding: data.encoding.to_s, uncompressed_length: data.length)
        end

        def decompress(data)
          raise 'Nil data' if data.nil?

          ::Zlib::Inflate.inflate(data)
        end
      end
    end
  end
end
