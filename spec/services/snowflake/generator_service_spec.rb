require 'rails_helper'

RSpec.describe Snowflake::GeneratorService do
  include ActiveSupport::Testing::TimeHelpers

  def timestamp_from(id)
    id >> (described_class::MACHINE_ID_BITS + described_class::SEQUENCE_BITS)
  end

  def machine_id_from(id)
    (id >> described_class::SEQUENCE_BITS) & ((1 << described_class::MACHINE_ID_BITS) - 1)
  end

  def sequence_from(id)
    id & described_class::MAX_SEQUENCE
  end

  describe '#next_id' do
    it 'returns a positive integer' do
      id = described_class.instance.next_id

      expect(id).to be_a(Integer)
      expect(id).to be_positive
    end

    it 'embeds the custom epoch-adjusted timestamp' do
      travel_to Time.utc(2026, 7, 31, 0, 0, 12.345) do
        id = described_class.instance.next_id
        expected_timestamp = ((Time.current.to_f * 1000) - described_class::CUSTOM_EPOCH).to_i

        expect(timestamp_from(id)).to eq(expected_timestamp)
        expect(sequence_from(id)).to eq(0)
        expect(machine_id_from(id)).to eq(0)
      end
    end

    it 'increments the sequence when called twice in the same millisecond' do
      travel_to Time.utc(2026, 8, 1, 0, 0, 0.999) do
        generator = described_class.instance
        first = generator.next_id
        second = generator.next_id

        expect(timestamp_from(first)).to eq(timestamp_from(second))
        expect(sequence_from(first)).to eq(0)
        expect(sequence_from(second)).to eq(1)
        expect(second - first).to eq(1)
      end
    end

    it 'resets the sequence when the millisecond changes' do
      generator = described_class.instance
      first_timestamp = nil

      travel_to Time.utc(2026, 8, 1, 12, 0, 0) do
        first = generator.next_id
        first_timestamp = timestamp_from(first)
        expect(sequence_from(first)).to eq(0)
      end

      travel_to Time.utc(2026, 8, 1, 12, 0, 1) do
        second = generator.next_id

        expect(timestamp_from(second)).to be > first_timestamp
        expect(sequence_from(second)).to eq(0)
      end
    end

    it 'generates unique ids across many calls in one millisecond' do
      travel_to Time.utc(2026, 8, 1, 0, 0, 1) do
        generator = described_class.instance
        ids = Array.new(100) { generator.next_id }

        expect(ids.uniq.size).to eq(100)
      end
    end

    it 'generates unique ids when called concurrently on one generator' do
      travel_to Time.utc(2026, 8, 1, 0, 0, 1) do
        generator = described_class.instance
        ids = Queue.new
        threads = Array.new(8) do
          Thread.new do
            25.times { ids << generator.next_id }
          end
        end
        threads.each(&:join)

        collected = 200.times.map { ids.pop }
        expect(collected.uniq.size).to eq(200)
      end
    end
  end
end
