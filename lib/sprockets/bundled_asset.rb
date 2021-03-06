require 'sprockets/asset'
require 'sprockets/errors'
require 'fileutils'
require 'set'
require 'zlib'

module Sprockets
  # `BundledAsset`s are used for files that need to be processed and
  # concatenated with other assets. Use for `.js` and `.css` files.
  class BundledAsset < Asset
    def initialize(environment, logical_path, filename)
      super

      processed_asset = environment.find_asset(filename, bundle: false)
      @required_assets = processed_asset.required_assets

      @dependency_paths  = processed_asset.dependency_paths
      @dependency_digest = processed_asset.dependency_digest
      @dependency_mtime  = processed_asset.dependency_mtime

      # Explode Asset into parts and gather the dependency bodies
      @source = to_a.map { |dependency| dependency.to_s }.join

      # Run bundle processors on concatenated source
      @source = environment.process(
        environment.bundle_processors(content_type),
        filename,
        @source
      )[:data]

      @mtime  = processed_asset.dependency_mtime
      @length = Rack::Utils.bytesize(source)
      @digest = environment.digest.update(source).hexdigest
    end

    # Initialize `BundledAsset` from serialized `Hash`.
    def init_with(environment, coder)
      super

      processed_asset = environment.find_asset(filename, bundle: false)
      @required_assets = processed_asset.required_assets

      if processed_asset.dependency_digest != dependency_digest
        raise UnserializeError, "processed asset belongs to a stale environment"
      end

      @source = coder['source']
    end

    # Serialize custom attributes in `BundledAsset`.
    def encode_with(coder)
      super

      coder['source'] = source
    end

    # Expand asset into an `Array` of parts.
    def to_a
      required_assets
    end
  end
end
