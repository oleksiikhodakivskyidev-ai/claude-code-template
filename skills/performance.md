---
name: performance
description: Detect performance issues in code and prevent inefficient implementations (CPU, memory, I/O).
---

# Performance Analysis

## Goal
Ensure code is efficient and avoids unnecessary CPU, memory, and I/O overhead.

---

## Scope

- Focus on changed code
- Expand only if performance risk detected
- Do not simulate or benchmark

---

## Detection Areas (priority)

### 1. Algorithmic complexity
- Nested loops (O(n^2)+)
- Repeated work inside loops
- Unnecessary recomputation

---

### 2. Memory usage
- Large in-memory collections
- Unbounded arrays/maps
- Copying large objects unnecessarily

---

### 3. I/O inefficiency
- Repeated DB/API calls in loops
- Missing batching
- Missing caching

---

### 4. Async / concurrency issues

#### Node / TS
- sequential `await` in loops
- blocking operations

#### Python
- blocking I/O in async code
- missing concurrency where needed

#### Go
- goroutine leaks
- unbounded concurrency

#### PHP
- repeated DB calls per request

---

### 5. Data structures
- wrong structure (array vs map)
- linear scans where hash lookup expected

---

### 6. Hot paths
- code inside frequently executed paths (loops, handlers)
- expensive operations in request lifecycle

---

## Red Flags

- O(n^2) or worse without reason
- repeated DB/API calls in loops
- full dataset loads when pagination possible
- unnecessary JSON serialization/deserialization
- large object cloning

---

## Output Rules

- Only real performance issues
- Include:
  - severity (high / medium / low)
  - file + location
  - short issue
  - fix direction
- No explanations
- No benchmarking suggestions

---

## Fix Rules

- Optimize only where needed
- Prefer:
  - batching
  - caching
  - correct data structures
  - reduced complexity
- No premature optimization

---

## Constraints

- No micro-optimizations
- No speculative issues
- No full rewrites unless critical
