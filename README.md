# dowsing

`dowsing` is a property-based test harness that feeds a large number of random operation sequences (over 1,000 mutations) generated using Haskell’s QuickCheck into a Node.js process to verify the correctness of state propagation and computation results in `@watervein/core` by comparing them with a reference model.

## What it Guarantees

- **Exact Match of Computation Results:** In complex dependency graphs, the final state resulting from any sequence of operations must match the Haskell reference model.
- **High-Load Tolerance:** State management must not fail even during prolonged continuous write/flush operations.
- **Absence of Infinite Loops:** No stack overflows caused by pointer cycles.
- **Performance Verification:** Detects abnormal slowdowns in `flush()` processing caused by unnecessary traversals or missed deallocations.

## Prerequisites

- **Node.js** (v18+)
- **GHC / runghc** (GHC 9.x Recommend)
- **Haskell Packages:** `QuickCheck`, `aeson`, `process`

## Usage

1. Setting Up JS Dependencies:
```bash
pnpm install
```

2. Installing Haskell Dependencies (One-time only):
```bash
cabal update
cabal install --lib QuickCheck aeson process
```

3. Run test
```bash
runghc Spec.hs
```

## License
We explicitly state that this software is licensed under the same [MIT license](LICENSE) as Watervein itself.