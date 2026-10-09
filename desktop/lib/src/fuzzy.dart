/// Same subsequence ranking used by the engine's local playlist/file filters.
/// Null means no match; stable callers preserve source order for equal scores.
int? fuzzyScore(String query, String target) {
  final q = query.toLowerCase().runes.toList();
  if (q.isEmpty) return 0;
  final text = target.toLowerCase().runes.toList();
  var qi = 0;
  var last = -2;
  var score = 0;
  const separators = ' -_/\\.:()[]';
  for (var i = 0; i < text.length; i++) {
    if (text[i] != q[qi]) continue;
    score++;
    if (i == 0) {
      score += 6;
    } else if (separators.contains(String.fromCharCode(text[i - 1]))) {
      score += 4;
    }
    if (i == last + 1) score += 4;
    last = i;
    if (++qi == q.length) return score;
  }
  return null;
}
