/// Semantic-ish version compare for dotted numbers (e.g. 1.4.9 vs 1.4.10).
/// Returns -1 if [a] < [b], 0 if equal, 1 if [a] > [b].
int compareVersion(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x < y) return -1;
    if (x > y) return 1;
  }
  return 0;
}

bool isVersionNewer(String remote, String local) =>
    compareVersion(remote, local) > 0;

List<int> _parts(String v) {
  final cleaned = v.trim();
  if (cleaned.isEmpty) return const [0];
  // Strip leading 'v' and ignore build metadata after '+' or pre-release '-'.
  var s = cleaned.startsWith('v') || cleaned.startsWith('V')
      ? cleaned.substring(1)
      : cleaned;
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);
  return s
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}