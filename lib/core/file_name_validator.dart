/// Política compartida de nombres; no depende de base de datos ni widgets.
class FileNameValidator {
  static String validateName(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.length > 180 ||
        RegExp(r'[\x00-\x1f/\\:*?"<>|]').hasMatch(name) ||
        name.endsWith('.')) {
      throw const FormatException(
        'Usá un nombre de 1 a 180 caracteres, sin / \\ : * ? " < > | ni punto final.',
      );
    }
    return name;
  }

}
