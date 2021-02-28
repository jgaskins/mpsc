require "./spec_helper"

require "../src/mpsc"

describe MPSC do
  it "can send and receive" do
    channel = MPSC::Channel(String).new
    channel.send "hi"
    channel.receive.should eq "hi"
  end

  it "blocks until a value is placed into the channel" do
    channel = MPSC::Channel(String).new
    spawn channel.send "hi"
    channel.receive.should eq "hi"
  end

  it "blocks for multiple messages" do
    channel = MPSC::Channel(String).new
    spawn { sleep 2.milliseconds; channel.send "second" }
    spawn { sleep 1.millisecond; channel.send "first" }
    channel.receive.should eq "first"
    channel.receive.should eq "second"
  end

  it "is unbounded" do
    channel = MPSC::Channel(String).new
    1_000_000.times { channel.send "hi" }
    1_000_000.times { channel.receive.should eq "hi" }
  end

  it "raises an error if closed while waiting" do
    channel = MPSC::Channel(String).new

    spawn channel.close

    expect_raises MPSC::Channel::ClosedError do
      channel.receive
    end
  end

  it "raises an error if closed before trying to receive" do
    channel = MPSC::Channel(String).new
    channel.close

    expect_raises MPSC::Channel::ClosedError do
      channel.receive
    end
  end

  it "raises an error if closed before trying to send" do
    channel = MPSC::Channel(String).new
    channel.close

    expect_raises MPSC::Channel::ClosedError do
      channel.send "hi"
    end
  end

  it "can receive in a nonblocking way with `receive?`" do
    channel = MPSC::Channel(String).new

    channel.receive?.should eq nil

    channel.send "hi"
    channel.receive?.should eq "hi"

    channel.receive?.should eq nil
  end

  it "blocks when receiving in another fiber" do
    channel = MPSC::Channel(String).new
    main_channel = Channel(String).new(10) # NOT an MPSC channel!

    spawn { main_channel.send channel.receive }
    spawn { channel.send "hi" }

    main_channel.receive.should eq "hi"
  end

  it "raises an error if you try to receive from a different fiber" do
    channel = MPSC::Channel(String).new
    main_channel = Channel(String).new(10) # NOT an MPSC channel!

    spawn { channel.receive }

    channel.send "hi"
    Fiber.yield

    expect_raises MPSC::Channel::MultipleFibersReceiveError do
      channel.receive
    end
  end
end
