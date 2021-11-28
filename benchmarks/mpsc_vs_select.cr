require "benchmark"
require "../src/mpsc"

puts "Empty channel"
empty_channel = Channel(String).new(10)
empty_mpsc = MPSC::Channel(String).new
value = nil
iterations = ENV.fetch("ITERATIONS", "1000").to_i
Benchmark.ips do |x|
  x.report "MPSC::Channel" { iterations.times { value = empty_mpsc.receive? } }
  x.report "Channel" do
    iterations.times do
      select
      when value = empty_channel.receive?
      else
        value = nil
      end
    end
  end
end

pp value
