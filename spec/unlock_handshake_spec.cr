require "./spec_helper"

require "../src/mpsc"

# Regression specs for the unchecked `@receive_mutex` handshake.
#
# `send` and `close` call `@receive_mutex.unlock` unconditionally, but that
# unlock is only legal while a receiver is parked in `receive` holding the
# lock. When no receiver holds it — the common case, since a consumer spends
# most of its time between `receive` calls — Crystal raises
# `Can't unlock Sync::MU that isn't held` from the caller.
#
# The reported failure is from `OpenTelemetry::BatchExporter`, which sends a
# trace then sleeps 100 ms: the second send lands with no parked receiver.
describe "MPSC::Channel unlock handshake" do
  describe "send" do
    it "accepts a send when no fiber is parked in receive" do
      channel = MPSC::Channel(String).new

      # No receiver has ever called `receive`, so nothing holds
      # `@receive_mutex`.
      channel.send "hi"

      channel.receive.should eq "hi"
    end

    it "accepts consecutive sends with no receiver in between" do
      channel = MPSC::Channel(String).new

      # BatchExporter#trace sends every trace of a batch back-to-back. The
      # exporter fiber drains them, but not between every send.
      channel.send "first"
      channel.send "second"

      channel.receive.should eq "first"
      channel.receive.should eq "second"
    end

    it "accepts a send while the receiver is parked in receive" do
      channel = MPSC::Channel(String).new
      received = Channel(String).new(1)

      # The receiver parks in `receive` and holds `@receive_mutex` before the
      # send runs. This is the one path the unconditional unlock was written
      # for.
      spawn { received.send channel.receive }
      Fiber.yield

      channel.send "hi"

      received.receive.should eq "hi"
    end

    it "accepts a send after the receiver took the last value and returned" do
      channel = MPSC::Channel(String).new
      received = Channel(String).new(2)

      # One receiver fiber, as the single-consumer contract requires. It takes
      # a value, returns from `receive`, then calls `receive` again.
      spawn do
        received.send channel.receive
        received.send channel.receive
      end
      Fiber.yield

      channel.send "first"
      received.receive.should eq "first"
      Fiber.yield

      # Second send with no parked receiver between the two receives.
      channel.send "second"
      received.receive.should eq "second"
    end
  end

  describe "close" do
    it "closes a channel that was never sent to" do
      channel = MPSC::Channel(String).new

      # Nothing ever unlocked `@receive_mutex`, so `close`'s unlock is stray.
      channel.close

      channel.closed?.should be_true
    end

    it "closes a channel that has already been sent to" do
      channel = MPSC::Channel(String).new
      channel.send "hi"

      channel.close

      channel.closed?.should be_true
    end

    it "is idempotent" do
      channel = MPSC::Channel(String).new
      channel.close
      channel.close

      channel.closed?.should be_true
    end
  end

  # Mirrors `OpenTelemetry::BatchExporter`: producers push every trace, the
  # single consumer drains a batch then sleeps, so sends land both while the
  # consumer is parked and while it is busy.
  describe "producer/consumer interleaving" do
    it "never raises across a burst of sends and a draining consumer" do
      channel = MPSC::Channel(Int32).new
      total = 10_000
      received = [] of Int32
      done = Channel(Nil).new

      spawn do
        while received.size < total
          if value = channel.receive?
            received << value
          else
            Fiber.yield
          end
        end
        done.send nil
      end

      total.times { |i| channel.send i }

      select
      when done.receive
      when timeout(5.seconds)
        fail "consumer did not drain #{total} values"
      end

      received.size.should eq total
      received.first.should eq 0
      received.last.should eq(total - 1)
    end
  end
end
