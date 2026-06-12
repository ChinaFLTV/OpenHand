import 'dart:async';

const Duration kOpenHandMinPeriodicTimerInterval = Duration(milliseconds: 250);
const Duration kOpenHandMaxPeriodicTimerInterval = Duration(hours: 24);

Duration safePeriodicTimerInterval(
  Duration requested, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
}) {
  final lower = min > Duration.zero ? min : kOpenHandMinPeriodicTimerInterval;
  final upper = max < lower ? lower : max;
  if (requested <= Duration.zero) return lower;
  if (requested < lower) return lower;
  if (requested > upper) return upper;
  return requested;
}

Timer startSafePeriodicTimer(
  Duration interval,
  void Function(Timer timer) callback, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
}) {
  return Timer.periodic(
    safePeriodicTimerInterval(interval, min: min, max: max),
    callback,
  );
}

Timer startNonOverlappingPeriodicTimer(
  Duration interval,
  FutureOr<void> Function(Timer timer) callback, {
  Duration min = kOpenHandMinPeriodicTimerInterval,
  Duration max = kOpenHandMaxPeriodicTimerInterval,
}) {
  var running = false;
  return startSafePeriodicTimer(
    interval,
    (timer) {
      if (running) return;
      running = true;
      Future.sync(() => callback(timer)).whenComplete(() => running = false);
    },
    min: min,
    max: max,
  );
}
