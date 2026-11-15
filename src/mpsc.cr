# TODO: Write documentation for `MPSC`
module MPSC
  VERSION = "0.1.0"

  class Channel(T)
    @queue = Deque(T).new
    @receive_mutex = Mutex.new(:unchecked)
    @queue_mutex = Mutex.new
    @has_sent = false

    # True while the receiver holds `@receive_mutex` and is waiting for the
    # next value. A producer may unlock the mutex only in this state; with no
    # receiver holding it the unlock is stray and Crystal raises
    # `Can't unlock Sync::MU that isn't held`.
    @waiting = false

    @assigned_to_fiber : Fiber? = nil
    getter? closed = false

    def send(value : T) : Nil
      @queue_mutex.synchronize do
        must_be_open!
        @queue << value
        @has_sent = true
        if @waiting
          # Hand the value to the parked receiver: release the mutex it holds.
          @waiting = false
          @receive_mutex.unlock
        end
      end
    end

    def receive : T
      must_be_open!

      @queue_mutex.synchronize do
        if @assigned_to_fiber && @assigned_to_fiber != Fiber.current
          raise MultipleFibersReceiveError.new("Trying to receive from multiple fibers")
        end
        @assigned_to_fiber ||= Fiber.current

        # When nothing was ever sent the mutex is unlocked, so the first lock
        # below succeeds and the second one parks us. When something was sent
        # the mutex may already be unlocked by a previous drain, so a single
        # lock takes the available permit.
        unless @has_sent
          @receive_mutex.lock
        end
        # We are about to park (or take a pending permit): from the producer's
        # point of view a receiver now holds the mutex.
        @waiting = true
      end

      # Lock for really real
      @receive_mutex.lock

      # Gotta check again after successfully achieving the lock in case another
      # fiber closed this while we were waiting.
      must_be_open!

      value = uninitialized T
      @queue_mutex.synchronize do
        value = @queue.shift

        if @queue.empty?
          # No more values: hold the mutex for the next value. A producer
          # unlocks it to hand one over.
          @waiting = true
        else
          # More values pending: unlock so the next `receive` does not block.
          @waiting = false
          @receive_mutex.unlock
        end
      end

      value
    end

    def receive? : T?
      # Peek and take in one atomic step. Calling `receive` after the check
      # would race: another consumer could drain the value and `receive` would
      # then block, defeating the non-blocking contract.
      @queue_mutex.synchronize do
        return if @queue.empty?
        if @assigned_to_fiber && @assigned_to_fiber != Fiber.current
          raise MultipleFibersReceiveError.new("Trying to receive from multiple fibers")
        end
        @assigned_to_fiber ||= Fiber.current
        return @queue.shift
      end
    end

    def close : Nil
      @queue_mutex.synchronize do
        @closed = true
        if @waiting
          @waiting = false
          @receive_mutex.unlock
        end
      end
    end

    private def sync(&)
      @mutex.synchronize { yield }
    end

    private def must_be_open!
      if closed?
        raise ClosedError.new("Channel was closed while waiting for value")
      end
    end

    class Error < ::Exception
    end

    class ClosedError < Error
    end

    class MultipleFibersReceiveError < Error
    end
  end
end
