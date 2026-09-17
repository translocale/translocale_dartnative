/// Formatting primitives used by generated messages.
library;

import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';

export 'package:intl/intl.dart' show DateFormat, NumberFormat;

bool _datesInitialized = false;

/// intl 0.20 installs its bundled date data synchronously before returning its
/// completed future. No platform, network, or asynchronous loading is involved.
void initializeMessageDates() {
  if (_datesInitialized) return;
  unawaited(initializeDateFormatting());
  _datesInitialized = true;
}
