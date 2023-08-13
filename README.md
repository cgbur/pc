# pc

No longer will your coworkers and friends make fun of you when you can't do
simple math in your head. Now you can do it in your terminal! `pc` is a simple
tool that calculates the percent difference between a list of numbers. It
supports reading from stdin or passing the numbers as arguments.

## Usage

```sh
pc 1 2 3 4 5
```

```sh
echo 1 2 3 4 5 | pc
```

Default delimiters are ` \n\r\n`, but you can specify more with the `-d` flag.

```sh
echo 1,2,3,4,5 | pc -d ","
```

```sh
pc --help
Usage: pc [numbers...] or ... | pc
Calculate the percent change between numbers.

Arguments:
  numbers...       : A sequence of numbers for which the percent change is to be calculated.

Special Arguments:
  -                 : Reads input from stdin.

Options:
  -h, --help        : Show this help message and exit.
  -d, --delimiters  : Specify extra delimiter(s) to use for parsing (default: " \t\n\r").
                      Example: echo "1,2,3" | pc -d ","

Symbols:
  ↑                 : Indicates a positive percent change.
  ↓                 : Indicates a negative percent change.
  →                 : Indicates no change.

Notes:
  - At least 2 numbers are required for calculation.
  - Invalid numbers in the sequence will be skipped.

Example:
  pc 10 20 30
  echo "10,20,30" | pc -d ","
```

## Installation

See the [releases](https://github.com/cgbur/pc/releases) page for prebuilt
binaries.

### Build from source

```sh
git clone https://github.com/cgbur/pc.git
cd pc
zig build -Doptimize=ReleaseSmall
cp zig-out/bin/pc ~/.local/bin/pc
```
