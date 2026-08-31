module Utils
  class Base62Service
    ALPHABET = [
      *('0'..'9'),
      *('a'..'z'),
      *('A'..'Z')
    ].freeze

    def self.encode(number)
      raise ArgumentError, 'number must be a non-negative integer' if !number.is_a?(Integer) || number.negative?

      return ALPHABET[0] if number.zero?

      digits = []
      while number > 0
        digits << ALPHABET[number % ALPHABET.length]
        number /= ALPHABET.length
      end

      digits.reverse.join
    end

    def self.decode(string)
      raise ArgumentError, 'cannot decode empty string' if string.blank?
      raise ArgumentError, 'input must be a string' if !string.is_a?(String)

      string.chars.reduce(0) do |acc, char|
        index = ALPHABET.index(char)
        raise ArgumentError, "invalid base62 character: #{char.inspect}" if index.nil?

        acc * ALPHABET.length + index
      end
    end
  end
end
