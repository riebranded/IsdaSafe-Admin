/// `'Last updated: {0}'.fill([when])` — fills positional placeholders. Stands
/// in for the farmer app's `trf` in the code ported from it (the admin panel
/// is English-only, so there's nothing to translate).
extension FillPlaceholders on String {
  String fill(List<Object?> args) {
    var text = this;
    for (var i = 0; i < args.length; i++) {
      text = text.replaceAll('{$i}', '${args[i]}');
    }
    return text;
  }
}
