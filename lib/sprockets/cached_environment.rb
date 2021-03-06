require 'sprockets/base'

module Sprockets
  # `Cached` is a special cached version of `Environment`.
  #
  # The expection is that all of its file system methods are cached
  # for the instances lifetime. This makes `Cached` much faster. This
  # behavior is ideal in production environments where the file system
  # is immutable.
  #
  # `Cached` should not be initialized directly. Instead use
  # `Environment#cached`.
  class CachedEnvironment < Base
    def initialize(environment)
      @environment = environment

      @default_external_encoding = environment.default_external_encoding

      # Copy environment attributes
      @logger            = environment.logger
      @context_class     = environment.context_class
      @cache             = environment.cache
      @asset_cache       = environment.asset_cache
      @trail             = environment.trail.cached
      @digest            = environment.digest
      @digest_class      = environment.digest_class
      @version           = environment.version
      @mime_types        = environment.mime_types
      @engines           = environment.engines
      @engine_mime_types = environment.engine_mime_types
      @preprocessors     = environment.preprocessors
      @postprocessors    = environment.postprocessors
      @bundle_processors = environment.bundle_processors
      @compressors       = environment.compressors
    end

    # No-op return self as cached environment.
    def cached
      self
    end
    alias_method :index, :cached

    # Cache `find_asset` calls
    def find_asset(*args)
      if asset = super
        if cached_asset = @asset_cache.get(asset.cache_key)
          cached_asset
        else
          @asset_cache.set(asset.cache_key, asset)
          asset
        end
      end
    end

    protected
      # Cache is immutable, any methods that try to clear the cache
      # should bomb.
      def expire_cache!
        raise TypeError, "can't modify immutable cached environment"
      end

      # Cache asset building in memory and in persisted cache.
      def build_asset(filename, options)
        key = "#{self.digest.hexdigest}:asset:#{filename}:#{file_hexdigest(filename)}:#{options[:bundle] ? '1' : '0'}"

        if asset = Asset.from_hash(self, cache._get(key))
          paths, digest = asset.send(:dependency_paths), asset.send(:dependency_digest)
          if dependencies_hexdigest(paths) == digest
            return asset
          end
        end

        if asset = super
          hash = {}
          asset.encode_with(hash)
          cache._set(key, hash)
          return asset
        end

        nil
      end
  end
end
