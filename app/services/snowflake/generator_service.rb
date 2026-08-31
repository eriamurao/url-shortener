module Snowflake
  class GeneratorService
    include Singleton

    CUSTOM_EPOCH = 1785542400000 # 2026-07-31 00:00:00 UTC

    TIMESTAMP_BITS = 41
    MACHINE_ID_BITS = 10
    SEQUENCE_BITS = 12

    # Decimal: 4095
    # Binary: 1111 1111 1111
    MAX_SEQUENCE = (1 << SEQUENCE_BITS) - 1

    def initialize
      @last_timestamp = -1
      @machine_id = machine_id
      @sequence = 0

      @mutex = Mutex.new
    end

    def next_id
      @mutex.synchronize do
        timestamp = current_timestamp_in_milliseconds

        if timestamp == @last_timestamp
          # bitwise AND to ensure sequence is within range
          @sequence = (@sequence + 1) & MAX_SEQUENCE

          # if sequence is 0, make sure the timestamp is at least the next millisecond
          timestamp = wait_for_next_millisecond(timestamp) if @sequence == 0
        else
          @sequence = 0
        end

        @last_timestamp = timestamp

        # 1. shift timestamp to the left by machine ID bits and sequence bits
        # 2. shift machine ID to the left by sequence bits
        # 3. combine the results using bitwise OR
        (timestamp << (MACHINE_ID_BITS + SEQUENCE_BITS)) |
          (@machine_id << SEQUENCE_BITS) |
          @sequence
      end
    end

    private

    # Subtract a custom epoch from the current timestamp so the resulting
    #   number is much smaller than raw Unix-epoch milliseconds. This keeps
    #   the timestamp component small enough to leave room, within the fixed
    #   total bit budget, for the machine_id and sequence bits packed alongside it.
    def current_timestamp_in_milliseconds
      ((Time.current.to_f * 1000) - CUSTOM_EPOCH).to_i
    end

    def wait_for_next_millisecond(current)
      current = current_timestamp_in_milliseconds while current <= @last_timestamp
      current
    end

    # Note: This is a temporary solution to get the machine ID.
    # This works for Kubernetes pods because it guarantees unique ordinal across all pods.
    def machine_id
      hostname = Socket.gethostname
      hostname[/\d+\z/].to_i
    end
  end
end
