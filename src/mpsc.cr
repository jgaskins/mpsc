# TODO: Write documentation for `MPSC`
module MPSC
  VERSION = "0.1.0"

  class Channel(T)
    @queue = Deque(T).new
    @receive_mutex = Mutex.new(:unchecked)
    @queue_mutex = Mutex.new
    @has_sent = false
    @assigned_to_fiber : Fiber? = nil
    getter? closed = false

    def send(value : T) : Nil
      @queue_mutex.synchronize do
        must_be_open!
        @queue << value
        @has_sent = true
        @receive_mutex.unlock
      end
    end

    def receive : T
      must_be_open!

      # First mutex lock will always succeed if nothing has been sent through
      # this channel before, so the first time we receive we need to double-
      # lock the mutex. I don't know of a better way.
      #
      # We wrap it in the queue mutex because the check and the lock must be a
      # single atomic operation.
      @queue_mutex.synchronize do
        if @assigned_to_fiber && @assigned_to_fiber != Fiber.current
          raise MultipleFibersReceiveError.new("Trying to receive from multiple fibers")
        end
        @assigned_to_fiber ||= Fiber.current
        @receive_mutex.lock unless @has_sent
      end

      # Lock for really real
      @receive_mutex.lock

      # Gotta check again after successfully achieving the lock in case another
      # fiber closed this while we were waiting.
      must_be_open!

      value = uninitialized T
      @queue_mutex.synchronize do
        value = @queue.shift

        # If the queue still has items in it, we unlock it so that the next
        # receive call won't block.
        unless @queue.empty?
          @receive_mutex.unlock
        end
      end

      value
    end

    def receive? : T?
      return if @queue.empty?
      receive
    end

    def close : Nil
      @closed = true
      @receive_mutex.unlock
    end

    private def sync
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
