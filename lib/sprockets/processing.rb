require 'sprockets/engines'
require 'sprockets/lazy_proxy'
require 'sprockets/legacy_proc_processor'
require 'sprockets/legacy_tilt_processor'
require 'sprockets/mime'
require 'sprockets/utils'

module Sprockets
  # `Processing` is an internal mixin whose public methods are exposed on
  # the `Environment` and `CachedEnvironment` classes.
  module Processing
    # Returns an `Array` of format extension `String`s.
    #
    #     format_extensions
    #     # => ['.js', '.css']
    #
    def format_extensions
      @trail.extensions - @engines.keys
    end

    # Returns an `Array` of `Processor` classes. If a `mime_type`
    # argument is supplied, the processors registered under that
    # extension will be returned.
    #
    # Preprocessors are ran before Postprocessors and Engine
    # processors.
    #
    # All `Processor`s must follow the `Template` interface. It is
    # recommended to subclass `Template`.
    def preprocessors(mime_type = nil)
      if mime_type
        @preprocessors[mime_type].dup
      else
        deep_copy_hash(@preprocessors)
      end
    end

    # Returns an `Array` of `Processor` classes. If a `mime_type`
    # argument is supplied, the processors registered under that
    # extension will be returned.
    #
    # Postprocessors are ran after Preprocessors and Engine processors.
    #
    # All `Processor`s must follow the `Template` interface. It is
    # recommended to subclass `Template`.
    def postprocessors(mime_type = nil)
      if mime_type
        @postprocessors[mime_type].dup
      else
        deep_copy_hash(@postprocessors)
      end
    end

    # Registers a new Preprocessor `klass` for `mime_type`.
    #
    #     register_preprocessor 'text/css', Sprockets::DirectiveProcessor
    #
    # A block can be passed for to create a shorthand processor.
    #
    #     register_preprocessor 'text/css', :my_processor do |context, data|
    #       data.gsub(...)
    #     end
    #
    def register_preprocessor(mime_type, klass, &block)
      @preprocessors[mime_type].push(wrap_processor(klass, block))
    end

    # Registers a new Postprocessor `klass` for `mime_type`.
    #
    #     register_postprocessor 'text/css', Sprockets::CharsetNormalizer
    #
    # A block can be passed for to create a shorthand processor.
    #
    #     register_postprocessor 'text/css', :my_processor do |context, data|
    #       data.gsub(...)
    #     end
    #
    def register_postprocessor(mime_type, klass, proc = nil, &block)
      proc ||= block
      @postprocessors[mime_type].push(wrap_processor(klass, proc))
    end

    # Remove Preprocessor `klass` for `mime_type`.
    #
    #     unregister_preprocessor 'text/css', Sprockets::DirectiveProcessor
    #
    def unregister_preprocessor(mime_type, klass)
      if klass.is_a?(String) || klass.is_a?(Symbol)
        klass = @preprocessors[mime_type].detect { |cls|
          cls.respond_to?(:name) && cls.name == "Sprockets::LegacyProcProcessor (#{klass})"
        }
      end

      @preprocessors[mime_type].delete(klass)
    end

    # Remove Postprocessor `klass` for `mime_type`.
    #
    #     unregister_postprocessor 'text/css', Sprockets::DirectiveProcessor
    #
    def unregister_postprocessor(mime_type, klass)
      if klass.is_a?(String) || klass.is_a?(Symbol)
        klass = @postprocessors[mime_type].detect { |cls|
          cls.respond_to?(:name) && cls.name == "Sprockets::LegacyProcProcessor (#{klass})"
        }
      end

      @postprocessors[mime_type].delete(klass)
    end

    # Returns an `Array` of `Processor` classes. If a `mime_type`
    # argument is supplied, the processors registered under that
    # extension will be returned.
    #
    # Bundle Processors are ran on concatenated assets rather than
    # individual files.
    #
    # All `Processor`s must follow the `Template` interface. It is
    # recommended to subclass `Template`.
    def bundle_processors(mime_type = nil)
      if mime_type
        @bundle_processors[mime_type].dup
      else
        deep_copy_hash(@bundle_processors)
      end
    end

    # Registers a new Bundle Processor `klass` for `mime_type`.
    #
    #     register_bundle_processor  'text/css', Sprockets::CharsetNormalizer
    #
    # A block can be passed for to create a shorthand processor.
    #
    #     register_bundle_processor 'text/css', :my_processor do |context, data|
    #       data.gsub(...)
    #     end
    #
    def register_bundle_processor(mime_type, klass, &block)
      @bundle_processors[mime_type].push(wrap_processor(klass, block))
    end

    # Remove Bundle Processor `klass` for `mime_type`.
    #
    #     unregister_bundle_processor 'text/css', Sprockets::CharsetNormalizer
    #
    def unregister_bundle_processor(mime_type, klass)
      if klass.is_a?(String) || klass.is_a?(Symbol)
        klass = @bundle_processors[mime_type].detect { |cls|
          cls.respond_to?(:name) && cls.name == "Sprockets::LegacyProcProcessor (#{klass})"
        }
      end

      @bundle_processors[mime_type].delete(klass)
    end

    # Internal: Run processors on filename and data.
    #
    # Returns Hash.
    def process(processors, filename, data)
      logical_path = logical_path_for(filename)

      input = {
        environment: self,
        cache: cache,
        filename: filename,
        root_path: paths.find { |path| filename[path] },
        logical_path: logical_path.chomp(File.extname(logical_path)),
        content_type: content_type_of(filename),
        data: data
      }

      required_paths    = []
      stubbed_assets    = Set.new
      dependency_paths  = Set.new
      dependency_assets = Set.new([filename])

      processors.each do |processor|
        begin
          result = processor.call(input.merge(data: data))
          case result
          when Hash
            data = result[:data]
            Array(result[:required_paths]).each { |p| required_paths << p }
            Array(result[:stubbed_assets]).each { |p| stubbed_assets << p }
            Array(result[:dependency_paths]).each { |p| dependency_paths << p }
            Array(result[:dependency_assets]).each { |p| dependency_assets << p }
          when String
            data = result
          else
            raise Error, "invalid processor return type: #{result.class}"
          end
        end
      end

      {
        data: data,
        required_paths: required_paths,
        stubbed_assets: stubbed_assets,
        dependency_paths: dependency_paths,
        dependency_assets: dependency_assets
      }
    end

    private
      def add_engine_to_trail(ext)
        @trail.append_extension(ext.to_s)

        if mime_type = @engine_mime_types[ext.to_s]
          if format_ext = extension_for_mime_type(mime_type)
            @trail.alias_extension(ext.to_s, format_ext)
          end
        end
      end

      def wrap_processor(klass, proc)
        if !proc
          if klass.class == Sprockets::LazyProxy || klass.respond_to?(:call)
            klass
          else
            LegacyTiltProcessor.new(klass)
          end
        elsif proc.respond_to?(:arity) && proc.arity == 2
          LegacyProcProcessor.new(klass.to_s, proc)
        else
          proc
        end
      end
  end
end
