// Group 1 is the modifiers, group 2 the class name, group 3 the parent.
// `(?<![@\w])` stops an annotation like `@sealed` or a word that ends in
// `abstract` from being read as a modifier. Modifiers must be on the same
// line as `class`, so a comment line that ends in "abstract" does not count.
final RegExp _classDeclaration = RegExp(
  r'(?<![@\w])((?:(?:abstract|sealed|base|final|interface|mixin)[ \t]+)*)'
  r'class\s+(\w+)\s+extends\s+(\w+)\b',
);

/// The classes that can be built, per source text, in the same order as
/// [sources]. A class counts when it extends [root] directly or through
/// other classes found in any of [sources] (an `abstract` base class, in
/// the same file or another). `abstract` and `sealed` classes are left out:
/// they have no constructor to call.
List<List<String>> buildableSubclasses(String root, List<String> sources) {
  List<List<RegExpMatch>> found = <List<RegExpMatch>>[
    for (String source in sources)
      _classDeclaration.allMatches(source).toList(),
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
              !m.group(1)!.contains(RegExp(r'abstract|sealed')))
            m.group(2)!,
      ],
  ];
}
