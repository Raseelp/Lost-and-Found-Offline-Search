// CLIP's byte -> unicode mapping, ported from the original Python.

class ByteEncoder {
  static final Map<int, String> byteToUnicode = _buildByteToUnicode();
  static final Map<String, int> unicodeToByte = byteToUnicode.map(
    (k, v) => MapEntry(v, k),
  );

  static Map<int, String> _buildByteToUnicode() {
    final List<int> bs = [];
    final List<int> cs = [];

    for (int i = 33; i <= 126; i++) {
      bs.add(i);
      cs.add(i);
    }

    for (int i = 161; i <= 172; i++) {
      bs.add(i);
      cs.add(i);
    }
    for (int i = 174; i <= 255; i++) {
      bs.add(i);
      cs.add(i);
    }

    int n = 0;
    for (int b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }

    final Map<int, String> result = {};
    for (int i = 0; i < bs.length; i++) {
      result[bs[i]] = String.fromCharCode(cs[i]);
    }

    return result;
  }

  static String encodeBytes(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(byteToUnicode[b]!);
    }
    return buffer.toString();
  }

  static List<int> decodeString(String text) {
    final List<int> bytes = [];
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      bytes.add(unicodeToByte[char]!);
    }
    return bytes;
  }
}
