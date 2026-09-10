# Contributing

This document outlines how to report bugs, suggest features, and submit code changes.

## How to Contribute

### Reporting Bugs

Check existing issues before opening a new one. If a new bug is found, open an issue and include:

- A summary of the problem.
- Steps to reproduce the bug.
- A minimal reproduction code snippet or place file, if applicable.
- Expected behavior versus actual results.

### Suggesting Features

To suggest an improvement or new feature:

- Open a feature request issue.
- Explain the problem the idea solves.
- Describe how the feature should work.

### Submitting Code Changes

Fork the repository, create a feature branch, and write unit tests for any changes. Ensure that tests pass and formatting/lint checks succeed before opening a Pull Request against `main`.

## Local Development

Follow these steps to set up Rogen locally and make changes.

### 1. Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) toolchain manager
- Roblox Studio

### 2. Setup

Clone the repository and install dependencies:

```bash
git clone https://github.com/LDGerrits/QuickZone.git
cd QuickZone
rokit install
```

### 3. Running Tests

Tests should be ran in an empty Roblox place.

1. Serve the test project file:
   ```bash
   rojo serve test.project.json
   ```
2. In Roblox Studio, connect to the Rojo server and start a play test with a player. Test results will automatically output to the Studio console.

### 4. Code Quality and Formatting

QuickZone uses Selene for linting and StyLua for code formatting:

```bash
selene src
stylua --check src tests
stylua src tests
```
