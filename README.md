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
↑    100%       1 → 2    
↑     50%       2 → 3    
↑  33.33%       3 → 4    
↑     25%       4 → 5   
```

### Custom Delimiters? No Problem:

```sh
❯ echo "15,20 3 6" | pc -d ","
↑  33.33%      15 → 20   
↓    -85%      20 → 3    
↑    100%       3 → 6 
```

### Fixed Calculation (relative to the first number):

```sh
❯ echo "128 221 150" | pc -f
↑  72.66%     128 → 221
↑  17.19%     128 → 150
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
