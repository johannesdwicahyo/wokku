module Preview
  module Provider
    class Base
      def self.parse(_payload)
        raise NotImplementedError, "#{name}.parse must be implemented by subclasses"
      end

      def self.normalize_action(raw, merged: nil)
        case raw.to_s
        when "opened", "reopened", "synchronize", "edited" then raw.to_sym
        when "closed" then merged ? :merged : :closed
        else raw.to_sym
        end
      end
    end
  end
end
