# `pc` - Terminal Percent Change 🚀

Ever been teased for not doing simple math in your head? Say no more! `pc` is
here to save the day. Effortlessly calculate percent differences between
numbers directly in your terminal 🧮⚡. A lightweight, blazing-fast tool that
makes math as simple as typing a command.

### Features 🌟

- **Fashionable Output:** Make your numbers look good 🎩.
- **Always Accurate:** Calculates percent change correctly every time 🎯.
- **Blazing Fast:** Don't wait, get your results instantly 🚀.
- **Zig-Powered:** Crafted with love using Zig ❤️.

## Usage 🛠️

### Basic Calculation:

```sh
❯ pc 1 2 3 4 5
↑    100%      2x  [     1 → 2     ]
↑     50%   1.50x  [     2 → 3     ]
↑  33.33%   1.33x  [     3 → 4     ]
↑     25%   1.25x  [     4 → 5     ]
```

### Friendly Sizes by Default 🎓

Large numbers are automatically converted into human-readable format by
converting them into friendly sizes like GiB, MiB, KiB, etc.

```sh
❯ echo "1124122523 2421252122" | pc
↑ 115.39%   2.15x  [  1.0GiB → 2.3GiB  ]
```

Want to see the raw numbers instead? No problem, just pass the `-r` option:

```sh
❯ echo "1124122523 2421252122" | pc -r
↑ 115.39%   2.15x  [1124122496 → 2421252096]
```

### Custom Delimiters? Sure!

```sh
❯ echo "15,20 3 6" | pc -d ","
↑  33.33%   1.33x  [    15 → 20    ]
↓    -85%   0.15x  [    20 → 3     ]
↑    100%      2x  [     3 → 6     ]
```

### Fixed Calculation (relative to the first number):

```sh
❯ echo "128 221 150" | pc -f
↑  72.66%   1.73x  [   128 → 221   ]
↑  17.19%   1.17x  [   128 → 150   ]
```

### Full Command List:

```sh
pc --help
```

## Installation 📥

### Grab Prebuilt Binaries

Get them from the [releases](https://github.com/cgbur/pc/releases) page.

### Or Build from Source 🛠️

With Zig, it's a breeze:

```sh
git clone https://github.com/cgbur/pc.git
cd pc
zig build -Doptimize=ReleaseSmall
cp zig-out/bin/pc ~/.local/bin/pc
```
