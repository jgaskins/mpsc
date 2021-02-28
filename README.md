# mpsc

MPSC is an implementation of a multi-producer/single-consumer channel. This is useful if you only ever consume a channel from within a single fiber.

MPSC channels are unbounded. Calling `send` will never block.

**Note:** This shard is _not_ suitable for consuming the same channel from multiple fibers, even if they don't consume it concurrently. Once you call `receive` from a fiber, the receiving end of the channel is locked to that fiber.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     mpsc:
       github: jgaskins/mpsc
   ```

2. Run `shards install`

## Usage

```crystal
require "mpsc"

channel = MPSC::Channel(String).new

spawn channel.send "hello"

channel.receive # "hello"
```

## Contributing

1. Fork it (<https://github.com/jgaskins/mpsc/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Reformat the code (`crystal tool format .`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
