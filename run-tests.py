import os
import subprocess
import difflib


def run_test(test_file):
    with open(test_file, "r") as f:
        lines = f.readlines()
        cmd = lines[0].strip()
        expected_output = "".join(lines[1:])
        actual_output = subprocess.check_output(cmd, shell=True).decode("utf-8").strip()

        return expected_output == actual_output, expected_output, actual_output


def print_diff(expected_output, actual_output):
    diff = difflib.unified_diff(
        expected_output.splitlines(keepends=True),
        actual_output.splitlines(keepends=True),
        fromfile="Expected",
        tofile="Actual",
    )
    print("\nDifference (Expected vs Actual):")
    print("".join(diff), end="")


def main():
    # modify path to use zig-out/bin/pc first
    os.environ["PATH"] = os.path.abspath("zig-out/bin") + ":" + os.environ["PATH"]

    # print which pc
    out = subprocess.check_output(["which", "pc"])
    print(f"Using pc: {out.decode('utf-8').strip()}")

    test_dir = "tests"
    passed = 0
    failed = 0
    files = sorted(os.listdir(test_dir))
    for test_file in files:
        success, expected_output, actual_output = run_test(
            os.path.join(test_dir, test_file)
        )
        if success:
            passed += 1
            print(f"\033[92m✔ {test_file}: Test passed\033[0m")
        else:
            failed += 1
            print(f"\033[91m✖ {test_file}: Test failed\033[0m")
            print_diff(expected_output, actual_output)
            print()
            print()

    # Summary
    print("\nTest Summary")
    print(f"Passed: \033[92m{passed}\033[0m")
    print(f"Failed: \033[91m{failed}\033[0m")

    if failed > 0:
        exit(1)


if __name__ == "__main__":
    main()
