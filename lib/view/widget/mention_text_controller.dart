import 'package:flutter/material.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';

typedef _Mention = ({TextRange range, Person person});

/// The search box's own controller. On top of ordinary typing it recognises named people in the text and highlights
/// them.
/// A person is typed plain, matched live against the People list, or picked from an "@" dropdown. A plain name counts
/// only if it belongs to exactly one person, and "@" is for two people sharing a name. [recognizedPeople] and
/// [queryWithoutMention] are what runSearch acts on: a photo filter that everyone mentioned has to be in, and the
/// words sent to CLIP without the names, which mean nothing to an image-similarity model.
class MentionTextEditingController extends TextEditingController {
  MentionTextEditingController({required this.peopleProvider});

  /// A function and not a fixed list, because people can be named after this controller is created and each
  /// keystroke should see the current list.
  final List<Person> Function() peopleProvider;

  /// The explicit "@" picks, revalidated on every change against their own stored range.
  ///
  /// An edit elsewhere that moves a pick enough to invalidate it drops it. The plain-text scan then picks the name up
  /// again from its new spot, unless the name is ambiguous. That narrow gap is known and left open, because closing
  /// it would take full position tracking.
  final List<_Mention> _explicit = [];

  List<_Mention> _mentions = const [];

  /// Every person recognised in the current text, left to right.
  List<Person> get recognizedPeople => _mentions.map((m) => m.person).toList();

  /// The words that count as an empty gap when they are all that is left between two removed names. "Raseel and
  /// Priya" leaves " and " between them, and "Raseel, Priya" leaves ", ". Without this, a search for two people
  /// would send only the connector word to CLIP.
  static const _bareConnectors = {'and', '&', 'with', ','};

  /// What to send to CLIP: the typed text with every recognised name, and the "@" that introduced it if any,
  /// removed and the whitespace collapsed.
  ///
  /// Each gap before the first mention, between two and after the last is kept as its own piece, so a bare connector
  /// can be checked and dropped alone without touching real content elsewhere in the text.
  String get queryWithoutMention {
    if (_mentions.isEmpty) return text.trim();
    final ascending = [..._mentions]
      ..sort((a, b) => a.range.start.compareTo(b.range.start));

    final gaps = <String>[];
    var cursor = 0;
    for (final m in ascending) {
      if (m.range.end > text.length || m.range.start < cursor) continue;
      var start = m.range.start;
      if (start > cursor && text[start - 1] == '@') start -= 1;
      gaps.add(text.substring(cursor, start));
      cursor = m.range.end;
    }
    gaps.add(text.substring(cursor));

    final cleaned = gaps.map((gap) {
      return _bareConnectors.contains(gap.trim().toLowerCase()) ? '' : gap;
    });
    return cleaned.join(' ').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// The partial name typed after an unfinished "@" right before the cursor, or null when the cursor is not in one.
  /// The dropdown filters its list by it. A space or a second "@" ends the name, so there is no dropdown for it any
  /// more.
  String? get activeMentionQuery {
    final pos = selection.baseOffset;
    if (pos < 0 || pos > text.length) return null;
    final upToCursor = text.substring(0, pos);
    final at = upToCursor.lastIndexOf('@');
    if (at == -1) return null;
    final between = upToCursor.substring(at + 1);
    if (between.contains(' ') || between.contains('@')) return null;
    return between;
  }

  /// Confirms [person] for the "@partial" just before the cursor.
  ///
  /// The pick is explicit, so unlike a live plain-text match it is never ambiguous, even if other people share the
  /// name. The "@" is dropped once picked, so a confirmed mention looks like a plain typed name that was recognised
  /// live.
  void selectMention(Person person) {
    final pos = selection.baseOffset;
    if (pos < 0 || pos > text.length) return;
    final upToCursor = text.substring(0, pos);
    final at = upToCursor.lastIndexOf('@');
    if (at == -1) return;
    final name = person.name ?? 'Unnamed';
    final newText = '${text.substring(0, at)}$name ${text.substring(pos)}';
    final newCursor = at + name.length + 1;
    _explicit.add((
      range: TextRange(start: at, end: at + name.length),
      person: person,
    ));
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Works out the mentions before the assignment and not after. The setter of the superclass notifies listeners, and
  /// what reacts to that, such as the highlighted repaint of the field and the dropdown, needs the mentions to match
  /// the new text already.
  @override
  set value(TextEditingValue newValue) {
    _recompute(newValue.text);
    super.value = newValue;
  }

  /// Keeps only the explicit picks whose exact text is still where it was left, then adds the plain-text matches.
  ///
  /// Names are tried longest first, so a full name wins over a shorter name that is a prefix of it. A name that
  /// belongs to more than one person is skipped, because "@" is how that is resolved. An explicit pick that sits
  /// next to a plain match, or overlaps it mid-edit, wins.
  void _recompute(String newText) {
    _explicit.removeWhere(
      (m) =>
          m.range.end > newText.length ||
          newText.substring(m.range.start, m.range.end) != m.person.name,
    );

    final named =
        peopleProvider().where((p) => (p.name ?? '').trim().isNotEmpty).toList()
          ..sort((a, b) => b.name!.length.compareTo(a.name!.length));

    final found = <_Mention>[..._explicit];
    final claimed = _explicit.map((m) => m.person.id).toSet();

    for (final person in named) {
      if (claimed.contains(person.id)) {
        continue;
      }
      final name = person.name!;
      final matches = _wholeWordMatches(newText, name);
      if (matches.isEmpty) continue;
      final sharedByOthers = named.any(
        (p) => p.id != person.id && p.name == name,
      );
      if (sharedByOthers) {
        continue;
      }
      final span = matches.first;
      final overlapsExplicit = _explicit.any(
        (e) => span.start < e.range.end && span.end > e.range.start,
      );
      if (overlapsExplicit) continue;
      found.add((range: span, person: person));
      claimed.add(person.id);
    }

    found.sort((a, b) => a.range.start.compareTo(b.range.start));
    _mentions = found;
  }

  /// True for an ASCII letter, digit or underscore.
  static bool _isWordChar(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  static List<TextRange> _wholeWordMatches(String haystack, String needle) {
    if (needle.isEmpty) return const [];
    final lowerHay = haystack.toLowerCase();
    final lowerNeedle = needle.toLowerCase();
    final matches = <TextRange>[];
    var start = 0;
    while (true) {
      final i = lowerHay.indexOf(lowerNeedle, start);
      if (i == -1) break;
      final end = i + needle.length;
      final before = i == 0 || !_isWordChar(haystack[i - 1]);
      final after = end == haystack.length || !_isWordChar(haystack[end]);
      if (before && after) matches.add(TextRange(start: i, end: end));
      start = i + 1;
    }
    return matches;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_mentions.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final highlight = (style ?? const TextStyle()).copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in _mentions) {
      if (m.range.start < cursor || m.range.end > text.length) continue;
      spans.add(TextSpan(text: text.substring(cursor, m.range.start)));
      spans.add(
        TextSpan(
          text: text.substring(m.range.start, m.range.end),
          style: highlight,
        ),
      );
      cursor = m.range.end;
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}
