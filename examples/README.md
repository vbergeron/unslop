# loadcheck

```
cargo run --example loadcheck
```

Prints what Scryer says while loading each Prolog source. `Machine::
consult_module_string` returns `()`, so a syntax error in the engine surfaces
only later, as an `existence_error` for whatever predicate did not get
defined — which is a long way from the actual cause. This asks the machine
directly, through `test_load_string`, and prints the error with its line
number.

It is how the four Scryer incompatibilities were found. Reach for it whenever
the binary reports `existence_error` for a predicate that plainly exists.
