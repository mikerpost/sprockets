require 'digest/sha1'

module Sprockets
  # `Utils`, we didn't know where else to put it!
  module Utils
    extend self

    # Prepends a leading "." to an extension if its missing.
    #
    #     normalize_extension("js")
    #     # => ".js"
    #
    #     normalize_extension(".css")
    #     # => ".css"
    #
    def normalize_extension(extension)
      extension = extension.to_s
      if extension[/^\./]
        extension
      else
        ".#{extension}"
      end
    end

    # Internal: Generate a hexdigest for a nested JSON serializable object.
    #
    # obj    - A JSON serializable object.
    # digest - Digest instance to modify
    #
    # Returns a String SHA1 digest of the object.
    def hexdigest(obj, digest = ::Digest::SHA1.new)
      case obj
      when String, Symbol, Integer
        digest.update "#{obj.class}"
        digest.update "#{obj}"
      when TrueClass, FalseClass, NilClass
        digest.update "#{obj.class}"
      when Array
        digest.update "#{obj.class}"
        obj.each do |e|
          hexdigest(e, digest)
        end
      when Hash
        digest.update "#{obj.class}"
        obj.map { |(k, v)| hexdigest([k, v]) }.sort.each do |e|
          digest.update(e)
        end
      else
        raise TypeError, "can't convert #{obj.inspect} into String"
      end

      digest.hexdigest
    end
  end
end
