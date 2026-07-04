import 'dart:async';
import 'dart:io';

class PeakRssSampler {
  int _baseline = 0;
  int _peak = 0;
  Timer? _timer;

  void start() {
    _baseline = ProcessInfo.currentRss;
    _peak = _baseline;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > _peak) _peak = rss;
    });
  }

  int stop() {
    _timer?.cancel();
    _timer = null;
    return _peak - _baseline;
  }
}
