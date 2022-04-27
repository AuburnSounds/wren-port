# wren-port

[Wren](https://wren.io/) is a small, fast, class-based concurrent scripting language.
`wren-port` is a port of the Wren programming language implementation to D, intended for embedding. This is useful is you want a `nothrow @nogc` fast interpreter in your D application.

The original Wren implementation is [here](https://github.com/wren-lang).


## Changes from original


### Build information

`System.isDebugBuild` allows to know if the -debug flag was used to build Wren, in case you want to disable some sort of live-scripting at release.

### Float literal terminal character

`1.0f`, `2L` and `2.0F` are valid Wren double literals in this fork.
This helps sharing bits of code between D and Wren.


### `$` operator

The new `$` operator is calling a host-provided function.
This allow to query entities with a nice syntax.

_Example:_
```wren
($"_imageKnob").hasTrail = false
```



_This translation was performed by [int3 Systems](https://0xcc.pw/) and sponsored by [Auburn Sounds](https://www.auburnsounds.com)._