# CSD359 - Lab Assignment 1
- The zig project is availble in the `zig_thread_test/` directory; it needs to be named this way to match the build script. The source code is available in `zig_thread_test/src`.

## Running Locally
1. Ensure `Zig v0.15.2` is availble on your system:
- Follow the instructions on this [site](https://ziglang.org/download/), preferrably using a package manager

2. Once zig is installed, run
```bash
zig version
# Outputs: 0.15.2
```
> **NOTE: Ensure the version matches exactly as there may be breaking changes between versions**

3. To compile run 
```bash
zig build
```
> **NOTE: Ensure that you are in the project root directory (`zig_thread_test`) or the compiler will not be able to find the appropriate build config**

4. The executable is available at `./zig-out/bin/zig_thread_test`. Run it by executing, while being in the project root directory (IMPORTANT) `zig_thread_test`:
```bash
  zig-out/bin/zig_thread_test
```
this can be used directly to run single tests configured to the current `config.json`. Use the `main.py` file to run a benchmark with varying input parameters.

6. To run the `main.py` file, ensure all python dependencies are installed
```bash
pip install -r requirements.txt
# or
uv sync
```

6. Run the `main.py` file
```bash
python3 main.py
# or
uv run main.py
```

## config.json
The `config.json` file is how the compiled binary decides execution modes
```json
{
  "n_threads": 64,
  "matrix": {
    "run": false,
    "schedule": "sequential",
    "M": 1,
    "N": 1,
    "P": 1
  },
  "prime": {
    "run": true,
    "schedule": "dynamic",
    "N": 10
  }
}
```
- `n_threads`: number of threads to use
- `matrix`: matmul specific config:
    - `run`: bool. Set to `true` when running matmul portion of the assignment, `false` otherwise. The two run fields are mutually exclusive
    - `schedule`: `enum{"sequential", "chunked", "cyclic", "dynamic"}`
    - `M`: mat1_rows
    - `N`: mat1_cols
    - `P`: mat2_cols
- `prime`: prime counter specific config:
    - `run`: bool. Set to `true` when running matmul portion of the assignment, `false` otherwise. The two run fields are mutually exclusive
    - `schedule`: `enum{"sequential", "chunked", "cyclic", "dynamic"}`
    - `N`: upper limit is set to `10^N`
