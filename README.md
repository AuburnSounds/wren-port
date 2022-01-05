# wren-port

[Wren](https://wren.io/) is a small, fast, class-based concurrent scripting language.
`wren-port` is a port of the Wren programming language implementation to D, intended for embedding. This is useful is you want a `nothrow @nogc` fast interpreter in your D application.

The original Wren implementation is [here](https://github.com/wren-lang).


## Changes from original

### `$` operator

The new `$` operator is calling a host-provided function.
This allow to query entities with a nice syntax.

_Example:_
```wren
($"_imageKnob").hasTrail = false
```



_This translation was performed by [int3 Systems](https://0xcc.pw/) and sponsored by [Auburn Sounds](https://www.auburnsounds.com)._