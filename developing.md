# Developing

## Requirements

* `make`
* `shellcheck` (package `ShellCheck` on fedora)
* `bats`
* `wget`
* `podman` (or `docker`)
* `jq`

## Lint

[ShellCheck](https://www.shellcheck.net/) is used to ensure the shell script is nice and tidy.

```bash
make validate
```

## Tests

Testing is done with [`bats`](https://github.com/bats-core/bats-core).

While it's possible to kick the tests by calling `bats ./test/`, many of the tests are written to use the script as built into a container image.
If you are making local changes and have not rebuilt the container, then they will be missed.

Best to kick off the build like:
```bash
make test-integration
```
This will rebuild the container if needed before running the tests.

##