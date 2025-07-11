import 'package:args/args.dart';
import 'package:yaml_test_suite_dart/yaml_test_suite.dart';

const _inputDir = 'directory';
const _outputDir = 'output';

final _argParser = ArgParser()
  ..addOption(
    _inputDir,
    abbr: 'd',
    mandatory: true,
    help: 'Directory with test suite data',
  )
  ..addOption(
    _outputDir,
    abbr: 'o',
    mandatory: true,
    help: 'Directory to write generated tests',
  );

extension on ArgResults {
  ({String testDataDir, String outDir}) get directories => (
    testDataDir: this[_inputDir].toString(),
    outDir: this[_outputDir].toString(),
  );
}

void main(List<String> args) async {
  print('Init generator!');
  final (:testDataDir, :outDir) = _argParser.parse(args).directories;

  await for (final directory in generateTestData(testDataDir)) {
    await copyFilesTo(outDir, directory);
  }
  print('Out generator!');
}
