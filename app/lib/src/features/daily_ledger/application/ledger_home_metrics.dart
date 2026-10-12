/// How many preferred metrics the home strip shows.
///
/// Phones show five when the width is under 390 logical pixels or text is
/// enlarged, and six otherwise. Wider layouts keep the first six.
int ledgerHomeMetricSlots({required double width, required double textScale}) {
  if (width >= 600) return 6;
  if (width < 390 || textScale > 1.3) return 5;
  return 6;
}
