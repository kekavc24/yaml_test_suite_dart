import 'dart:collection';
import 'dart:convert';

/// Start of json map
const _jsonMapOpen = '{';

/// End of json map
const _jsonMapClose = '}';

/// Start of json list
const _jsonListOpen = '[';

/// End of json list
const _jsonListClose = ']';

/// Start/end of json value for a key/value
const _jsonQuote = '"';

/// Character used to escape trailing line breaks in json generated to
/// validate parsed YAML
const _occludedLF = '↵';

/// Character used to escape hard tabs in json generated to validate parsed YAML
const _occludedTAB = '»';

/// Utility map for matching [_jsonListClose] and [_jsonMapClose] to their
/// counterparts
final _jsonAntiPartner = {
  _jsonMapClose: _jsonMapOpen,
  _jsonListClose: _jsonListOpen,
};

/// Other delimiters used in json.
final _jsonIgnored = {':', ','};

/// Decodes and saves the json present in the [buffer]. Any [_occludedLF] and
/// [_occludedTAB] are replaced with `\n` and `\t` respectively to revert the
/// json to a format compatible with YAML
void _saveJson(List<String> jsonInputs, StringBuffer buffer) {
  jsonInputs.add(
    json
        .decode(buffer.toString())
        .toString()
        .replaceAllMapped(
          RegExp('[$_occludedLF$_occludedTAB]'),
          (m) => m[0]! == _occludedLF ? '\n' : '\t',
        ),
  );

  buffer.clear();
}

/// Skips any whitespace (line breaks included) present in the [json]
/// beginning at the [currentIndex]. Exits immediately if the [currentIndex]
/// is greater than the length of the [json].
int _skipWhitespace(String json, int currentIndex) {
  final maxLen = json.length;
  var index = currentIndex;

  while (index < maxLen && json[index].trim().isEmpty) {
    ++index;
  }

  return index;
}

/// Scans a quoted key/value and occludes any line feeds and/or hard tabs
/// encountered. If [saveAsJson] is `true`, the content is immediately
/// saved and [buffer] cleared after scanning the entire value.
int _scanJsonQuoted(
  List<String> jsonInputs, {
  required String testID,
  required String jsonString,
  required int currentIndex,
  required StringBuffer buffer,
  required bool saveAsJson,
}) {
  if (currentIndex >= jsonString.length) return currentIndex;

  final maxLen = jsonString.length;

  buffer.write(_jsonQuote);

  var expectedIndex = currentIndex + 1;

  /// YAML styles can have line breaks/tabs. Replace in accordance with the
  /// test suite guide/README:
  ///   - "↵" - for line feed or carriage return
  ///   - "»" - for a hard tab
  fixer:
  for (expectedIndex; expectedIndex < maxLen; expectedIndex++) {
    final char = jsonString[expectedIndex];

    switch (char) {
      case _jsonQuote when jsonString[expectedIndex - 1] != r'\':
        break fixer;

      case '\r':
        {
          ++expectedIndex;
          continue occluder;
        }

      occluder:
      case '\n':
        buffer.write(_occludedLF);

      case '\t':
        buffer.write(_occludedTAB);

      default:
        buffer.write(char);
    }
  }

  // Be safe.
  if (expectedIndex >= maxLen || jsonString[expectedIndex] != _jsonQuote) {
    throw Exception(
      'Dirty json found in test with ID: $testID. No closing quote for '
      'string starting at offset #$currentIndex',
    );
  }

  buffer.write(_jsonQuote);

  if (saveAsJson) {
    _saveJson(jsonInputs, buffer);
  }

  return ++expectedIndex;
}

/// Scans an unquoted YAML value as a valid json value restricted to a single
/// line. This function behaves similarly to [_scanJsonQuoted] but its scope
/// limited.
int _scanInlineUnquoted(
  List<String> jsonInputs, {
  required String testID,
  required String jsonString,
  required int currentIndex,
  required StringBuffer buffer,
  required bool saveAsJson,
}) {
  if (currentIndex >= jsonString.length) return currentIndex;

  final maxLen = jsonString.length;
  var index = currentIndex;

  for (index; index < maxLen; index++) {
    final char = jsonString[index];

    // An unquoted YAML json value
    if (char case _jsonMapClose || _jsonListClose || ',' || ':' || ' '
        when !saveAsJson) {
      break;
    } else if (char case '\r' || '\n') {
      break; // Inline values cannot have line break or whitespace
    }

    buffer.write(char);
  }

  if (saveAsJson) {
    jsonInputs.add(buffer.toString());
    buffer.clear();
  }

  return index;
}

/// Extracts multiple json objects dumped in a way that is contrary to the
/// json format.
///
/// Example:
/// ```json
/// {
///   "key": "value"
/// }
/// ["sequence"]
/// ```
///
/// While this is invalid json, this dump is somewhat valid if the yaml parsed
/// was:
///
/// ```yaml
/// ---
/// key: value
/// ---
/// - sequence
/// ```
///
/// Ergo, this function attempts to extract json dumps provided by the test
/// suite in a way that it can be parsed as valid json.
///
/// The error detection capability of this function is limited and it may
/// assume the string being saved is valid. However, the standard `Dart` json
/// decoder that performs the actual parsing will catch any errors (which
/// is rare for our use case).
///
/// Also, this function is not optimized for performance evidenced by the
/// double work of scanning and parsing. Only correctness! :)
void extractMultiDocJsonChunks(
  String testID,
  List<String> jsonInputs,
  String jsonString,
) {
  final queue = Queue<(int, String)>(); // Tracks map/list nodes seen.

  var index = 0;
  final maxLength = jsonString.length;

  final buffer = StringBuffer();

  void addToBuffer(String char) => buffer.write(char);

  void nextChar() => ++index;

  while (index < maxLength) {
    final char = jsonString[index];

    switch (char) {
      case _jsonListOpen || _jsonMapOpen:
        {
          queue.add((index, char));
          addToBuffer(char);
          nextChar();
        }

      case _jsonListClose || _jsonMapClose:
        {
          final partner = _jsonAntiPartner[char]!;

          if (queue.isEmpty) {
            throw Exception(
              'Found "$char" but "$partner" was not in queue already'
              ' in testID: $testID',
            );
          }

          final (offset, delim) = queue.removeLast();

          if (delim != partner) {
            throw Exception(
              'Expected "$partner" for "$char" but found "$delim"'
              ' in testID: $testID at offset #$index',
            );
          }

          addToBuffer(char);

          if (queue.isEmpty) {
            _saveJson(jsonInputs, buffer);
          }

          nextChar();
        }

      case _ when char.trim().isEmpty:
        index = _skipWhitespace(jsonString, index);

      case _ when _jsonIgnored.contains(char):
        {
          addToBuffer(char);
          nextChar();
        }

      case _jsonQuote:
        index = _scanJsonQuoted(
          jsonInputs,
          testID: testID,
          jsonString: jsonString,
          currentIndex: index,
          buffer: buffer,
          saveAsJson: queue.isEmpty,
        );

      default:
        index = _scanInlineUnquoted(
          jsonInputs,
          testID: testID,
          jsonString: jsonString,
          currentIndex: index,
          buffer: buffer,
          saveAsJson: queue.isEmpty,
        );
    }
  }
}
