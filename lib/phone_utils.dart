/// Normalise un numéro de téléphone français au format international (+33...).
/// Évite les doubles préfixes (ex: "33+336xxxxx" → "+336xxxxx").
String normalizePhone(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  // Cas "33+336..." ou "+33+336..." : garder uniquement le dernier +33
  final plus33Index = s.lastIndexOf('+33');
  if (plus33Index >= 0) {
    s = s.substring(plus33Index);
  } else if (s.startsWith('33') && s.length >= 10) {
    s = '+$s';
  } else if (s.startsWith('0') && s.length == 10) {
    s = '+33${s.substring(1)}';
  } else if (!s.startsWith('+')) {
    s = '+$s';
  }
  return s;
}
