require 'rails_helper'

RSpec.describe Utils::Base62Service do
  describe '.encode' do
    it 'encodes zero as the first alphabet character' do
      expect(described_class.encode(0)).to eq('0')
    end

    it 'encodes small positive integers without leading zeros' do
      expect(described_class.encode(1)).to eq('1')
      expect(described_class.encode(61)).to eq('Z')
      expect(described_class.encode(62)).to eq('10')
    end

    it 'round-trips through decode for large positive integers' do
      value = (62**4) + 12_345_678

      encoded = described_class.encode(value)
      expect(encoded).to eq('1PNFQ')
      expect(described_class.decode(encoded)).to eq(value)
    end

    it 'raises an error for negative numbers' do
      expect { described_class.encode(-1) }.to raise_error(ArgumentError, 'number must be a non-negative integer')
      expect { described_class.encode(-100) }.to raise_error(ArgumentError, 'number must be a non-negative integer')
    end

    it 'raises an error for non-integer numbers' do
      expect { described_class.encode(1.5) }.to raise_error(ArgumentError, 'number must be a non-negative integer')
      expect { described_class.encode('1') }.to raise_error(ArgumentError, 'number must be a non-negative integer')
    end

    it 'raises an error for nil input' do
      expect { described_class.encode(nil) }.to raise_error(ArgumentError, 'number must be a non-negative integer')
    end
  end

  describe '.decode' do
    it 'decodes strings encoded by encode' do
      expect(described_class.decode('0')).to eq(0)
      expect(described_class.decode('1')).to eq(1)
      expect(described_class.decode('10')).to eq(62)
    end

    it 'decodes strings with leading zeros for the same value' do
      expect(described_class.decode('01')).to eq(1)
      expect(described_class.decode('001')).to eq(1)
      expect(described_class.decode('00')).to eq(0)
    end

    it 'does not treat every leading zero string as zero' do
      expect(described_class.decode('0a')).to eq(10)
    end

    it 'normalizes when re-encoding a non-canonical string' do
      expect(described_class.encode(described_class.decode('01'))).to eq('1')
    end

    it 'raises an error for empty string or nil input' do
      expect { described_class.decode('') }.to raise_error(ArgumentError, 'cannot decode empty string')
      expect { described_class.decode(nil) }.to raise_error(ArgumentError, 'cannot decode empty string')
    end

    it 'raises an error for non-string input' do
      expect { described_class.decode(1) }.to raise_error(ArgumentError, 'input must be a string')
    end

    it 'raises ArgumentError for characters outside the alphabet' do
      expect { described_class.decode('ab!') }.to raise_error(ArgumentError, /invalid base62 character: "!"/)
    end
  end
end
