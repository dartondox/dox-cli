// Group 1 is the modifiers, group 2 the class name, group 3 the parent.
// `(?<![@\w])` stops an annotation like `@sealed` or a word that ends in
// `abstract` from being read as a modifier. Modifiers must be on the same
// line as `class`, so a comment line that ends in "abstract" does not count.
final RegExp _classDeclaration = RegExp(
  r'(?<![@\w])((?:(?:abstract|sealed|base|final|interface|mixin)[ \t]+)*)'
  r'class\s+(\w+)(?:\s*<[^{};]*?>)?\s+extends\s+(\w+)\b',
);

/// [source] without comments and without the text of string literals, so
/// code inside them is not read as a class. Handles `//`, nested `/* */`,
/// raw strings and triple-quoted strings. A `${}` in a string is not
/// parsed: the string ends at its closing quote.
String stripCommentsAndStrings(String source) {
  StringBuffer out = StringBuffer();
  int i = 0;
  int n = source.length;
  while (i < n) {
    String c = source[i];
    String next = i + 1 < n ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
    } else if (c == '/' && next == '*') {
      int depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      out.write(' ');
    } else if (c == "'" || c == '"') {
      bool raw = i > 0 && source[i - 1] == 'r';
      String quote = source.startsWith(c * 3, i) ? c * 3 : c;
      i += quote.length;
      while (i < n && !source.startsWith(quote, i)) {
        // a backslash skips the next character, unless the string is raw
        i += (!raw && source[i] == '\\') ? 2 : 1;
      }
      i += quote.length;
      out.write('$quote$quote');
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// The classes that can be built, per source text, in the same order as
/// [sources]. A class counts when it extends [root] directly or through
/// other classes found in any of [sources] (an `abstract` base class, in
/// the same file or another). `abstract`, `sealed` and private (`_Name`)
/// classes are left out: they can not be built from another file.
List<List<String>> buildableSubclasses(String root, List<String> sources) {
  List<List<RegExpMatch>> found = <List<RegExpMatch>>[
    for (String source in sources)
      _classDeclaration.allMatches(stripCommentsAndStrings(source)).toList(),
  ];
  Set<String> known = <String>{root};
  bool changed = true;
  while (changed) {
    changed = false;
    for (List<RegExpMatch> matches in found) {
      for (RegExpMatch m in matches) {
        if (known.contains(m.group(3)) && known.add(m.group(2)!)) {
          changed = true;
        }
      }
    }
  }
  return <List<String>>[
    for (List<RegExpMatch> matches in found)
      <String>[
        for (RegExpMatch m in matches)
          if (known.contains(m.group(3)) &&
              !m.group(2)!.startsWith('_') &&
              !m.group(1)!.contains(RegExp(r'abstract|sealed')))
            m.group(2)!,
      ],
  ];
}
