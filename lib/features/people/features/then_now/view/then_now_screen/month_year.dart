part of '../then_now_screen.dart';

String _monthYear(DateTime t) => '${_short[t.month - 1]} ${t.year}';

const _short = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
