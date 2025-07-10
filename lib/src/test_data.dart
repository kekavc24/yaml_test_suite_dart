import 'dart:io';
import 'package:async/async.dart';
import 'package:path/path.dart' as path;
import 'package:yaml_test_suite_dart/src/json_utils.dart';

const _defaultJsonPath = 'jsonToDartStr';

/// A single level directory with YAML test suite data
typedef TestDirectory = ({
  /// Name of the directory. Remains unchanged if the directory was not a
  /// subdirectory to a top level directory
  String name,

  /// Immutable files that must be present even when moving the directory.
  List<File> filesToMove,

  /// Json input to validate if data was successfully parsed
  String? comparableJson,
});

const _metaPath = '===';
const _jsonInputPath = 'in.json';
const _yamlInputPath = 'in.yaml';
const _errPath = 'error';

final _miscellaneousDir = {'meta', 'tags', 'name', '.git'};

/// Extracts test data to be regenerated.
Future<TestDirectory> _extractData(
  String testID,
  Stream<File> testFiles,
) async {
  void freeThrow(String message) => Exception(message);

  void utilFunc(String path, bool Function() checker, void Function() body) {
    if (!checker()) {
      freeThrow('Duplicate "$path" files found');
    }
    return body();
  }

  var hasMetaDesc = false; // General description of the test
  var hasYamlInput = false; // Yaml input to be parsed
  var isErrorTest = false;

  final files = <File>[];
  final jsonInput = <String>[]; // Json comparison if valid

  await for (final file in testFiles) {
    switch (path.basename(file.path)) {
      case _errPath:
        isErrorTest = true;

      case _jsonInputPath:
        utilFunc(
          _jsonInputPath,
          () => jsonInput.isNotEmpty,
          () => extractMultiDocJsonChunks(
            testID,
            jsonInput,
            file.readAsStringSync().trim(),
          ),
        );

      case _yamlInputPath:
        utilFunc(_yamlInputPath, () => hasYamlInput, () {
          hasYamlInput = true;
          files.add(file);
        });

      case _metaPath:
        utilFunc(_metaPath, () => hasMetaDesc, () {
          hasMetaDesc = true;
          files.add(file);
        });

      default:
        continue;
    }
  }

  // Error tests never have json input
  if (isErrorTest && jsonInput.isNotEmpty) {
    freeThrow(
      'Error test found with json input to validate found at test with ID:'
      ' $testID',
    );
  } else if (files.length != 2 || (!isErrorTest && jsonInput.isEmpty)) {
    freeThrow('Test "$testID" has incomplete data not suitable for testing');
  }

  return (
    name: testID,
    filesToMove: files,
    comparableJson: jsonInput.toString(),
  );
}

/// Iterates nested directory until a single level directory with test data is
/// found and its data extracted
Stream<TestDirectory> _extractCompleteTestData(
  String baseDirName,
  Directory directory,
) async* {
  final queue = StreamQueue(directory.list());

  if (!await queue.hasNext) {
    throw Exception(
      'No tests where found in for test ID: $baseDirName',
    );
  }

  // We assume it's a data directory and iterate it as such
  if (await queue.peek is File) {
    yield await _extractData(
      baseDirName,
      queue.rest.where((f) => f is File).cast<File>(),
    );
  } else {
    // Iterate and throw if we see a file
    while (await queue.hasNext) {
      final fse = await queue.next;

      if (fse is! Directory) {
        throw Exception(
          'Expected a test directory but found a ${fse.runtimeType} for test'
          ' with ID: $baseDirName',
        );
      }

      yield* _extractCompleteTestData(
        '$baseDirName-${path.basename(fse.path)}',
        fse,
      );
    }
  }

  await queue.cancel(immediate: true);
}

/// Generates an abstraction of the actual directory with its test suite data
Stream<TestDirectory> generateTestData(String directory) async* {
  final testDir = Directory(directory);

  // We must see get a valid test directory
  assert(testDir.existsSync(), '"$directory" doesn\'t exist!');

  /// YAML test data is arranged in directories in 2 distinct formats:
  ///   - Tests that should parse successfully
  ///   - Tests that should fail due to invalid yaml
  ///
  /// Tests that should parse (pun intended) successfully have:
  ///   - Canonical test description
  ///   - Expected output as json
  ///   - Input as yaml
  ///   - output as yaml by tool (not supported yet by this tool)
  ///
  /// Tests that should fail have:
  ///   - Canonical test description
  ///   - A blank error file
  ///   - Input as yaml
  await for (final dir in testDir.list()) {
    if (dir is! Directory) {
      throw Exception(
        'Found a test file. Expected a test directory at'
        '"${dir.absolute.path}"',
      );
    }

    final normalized = path.basename(dir.path);

    // For our use case, the said directories serve no purpose
    if (_miscellaneousDir.contains(normalized)) continue;

    yield* _extractCompleteTestData(normalized, dir);
  }
}

/// Deletes a [file] that is a [Directory] or [File]
Future<void> _deleteIfPresent(
  FileSystemEntity file, {
  required bool recursive,
}) async {
  if (await file.exists()) {
    await file.delete(recursive: recursive);
  }
}

/// Moves test data to the desired test directory
Future<String> copyFilesTo(
  String absoluteRootDir,
  TestDirectory directoryToMove,
) async {
  final (:name, :filesToMove, :comparableJson) = directoryToMove;

  final dirPath = path.joinAll([absoluteRootDir, name]);
  final dir = Directory(dirPath);

  // Remove directory. May have stale data
  _deleteIfPresent(dir, recursive: true);
  await dir.create();

  for (final file in filesToMove) {
    await file.copy(
      path.joinAll(
        [dirPath, path.basename(file.path)],
      ),
    );
  }

  /// Successful tests may have a cleaned json input to ensure validity of the
  /// data parsed
  if (comparableJson != null) {
    final file = File(path.joinAll([dirPath, _defaultJsonPath]));
    _deleteIfPresent(file, recursive: false); // Impossible. Just to be safe
    await file.writeAsString(comparableJson);
  }

  return dirPath;
}
