# yaml_test_suite_dart

This is a fork of the official [YAML Test Suite][yaml_link]. The tests are unaltered.

## Structure

The repo has 4 branches:

1. `data` - this branch actively tracks the official test suite's `data` branch and will be synced from time to time if any raw tests are added.
2. `data-local` - our unaltered fork copy that is used to generate tests. Synced changes will be merged from the `data` branch.
3. `main` - contains Dart code that generates the tests from the `data-local`. The code here will rarely change.
4. `generated-tests-dart` - contains generated test files. You should use the test files present in this branch.

## Generated Tests

The test files generated in this repo are similar to those in the official test suite. The key differences include:

* The `in.json` file is replaced by a `jsonToDartStr` file that contains a string that resembles strings generated when an object's `toString` method is called in `Dart`. This was done for simplicity's sake since some `in.json` files contain multiple json nodes dumped in a format that is invalid as json but somewhat valid in YAML.

> [!NOTE]
> You can still use the official YAML test suite. No special changes have been made. The `jsonToDartStr` is a subjective change as most objects in Dart (and most programming languages) implement a `toString()` method that outputs the object as a simple string. The rationale for this change is explained below.

```json
{"key": "value"}
"what? another value here?"
["bruh", "is this valid?"]
```

The json content above can be represented in YAML as:

```yaml
---
key: value
---
"what? another value here?"
---
- bruh
- is this valid
```

The repo currently regenerates the `in.json` file as a simple string:

```shell
# Collects all the json nodes to an array

[{key: value}, what? another value here?, [bruh, is this valid]]
```

* Error tests only have the `===` file (label) and an `in.yaml` file. Each parser's test must fail but the error message may be different?

## TLDR

Each test folder in the `generated-tests-dart` is a single level directory. You don't have to worry about nested directories.

Test folder whose YAML inputs must be successfully parsed include:

* `===` - label
* `in.yaml` - yaml input
* `jsonToDartStr` - simple string representing the underlying object. If multiple docs are in play, then the string is an array of the objects as strings
* `out.yaml` - yaml output if the node was dumped. May differ from `in.yaml`.

Test folders whose YAML inputs must result in a parser failure only have:

* `===`
* `in.yaml`

## I need the `jsonToDartStr` dumped differently

Just create an issue and we can work something out.

[yaml_link]: https://github.com/yaml/yaml-test-suite
