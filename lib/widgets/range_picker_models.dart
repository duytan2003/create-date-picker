import 'package:flutter/material.dart';

/// How a confirmed day was worked.
enum WorkStatus {
  /// Worked at the office / on site.
  onsite,

  /// Worked somewhere else.
  offsite,
}

/// A day that is already confirmed ("Đã Xác nhận PCCT") and how it was worked.
@immutable
class ConfirmedDay {
  /// [date] is reduced to its calendar day (the time of day is dropped).
  ConfirmedDay(DateTime date, this.status)
    : date = DateTime(date.year, date.month, date.day);

  /// The day, always at midnight.
  final DateTime date;

  /// How it was worked.
  final WorkStatus status;

  @override
  bool operator ==(Object other) =>
      other is ConfirmedDay && other.date == date && other.status == status;

  @override
  int get hashCode => Object.hash(date, status);

  @override
  String toString() => 'ConfirmedDay($date, ${status.name})';
}

/// Where the picker gets its data from and where it sends the confirmations.
/// The app writes one small class that implements this and gives it to
/// `CreateRangeDatePicker(repository: ...)`; the picker does the rest (loading
/// the cycle on screen, drawing the dots, the confirm button).
///
/// Dates are plain calendar days. Build them with `DateTime(year, month,
/// day)` and never convert them to UTC: a day parsed from
/// `2026-10-26T00:00:00Z` lands on the day before in Vietnam.
abstract class TimesheetRepository {
  /// Const constructor so subclasses can be const.
  const TimesheetRepository();

  /// The days between [from] and [to] (both included) that are already
  /// confirmed, with their status. A day that is not in the answer is not
  /// confirmed. The picker asks for the cycle on screen plus 6 days on each
  /// side, because the grid shows whole weeks and so a few days of the
  /// neighbouring cycles.
  Future<List<ConfirmedDay>> loadConfirmed(DateTime from, DateTime to);

  /// Confirms [days] (the valid days of the range the user picked: skipped
  /// rest days and confirmed days are already left out) and returns what was
  /// saved, with the status of each day. The status comes from the app (for
  /// example the Onsite/Offsite choice the user made next to the calendar), so
  /// it is the repository that adds it. Throw to say it failed: the picker
  /// then shows a message and keeps the range.
  ///
  /// The server must check the rules again (starts on the earliest
  /// unconfirmed day, no gaps, nothing in the future, inside the cycle): the
  /// app can be bypassed.
  Future<List<ConfirmedDay>> confirm(List<DateTime> days);
}

/// A [TimesheetRepository] that keeps everything in memory. Good for a demo
/// and for tests; a real app writes its own repository.
class InMemoryTimesheetRepository extends TimesheetRepository {
  /// Starts with [initial] days confirmed. [latency] is how long every call
  /// takes. [statusForConfirm] answers which status new days get (default:
  /// onsite); it is where an app would read its Onsite/Offsite choice.
  InMemoryTimesheetRepository({
    Iterable<ConfirmedDay> initial = const [],
    this.latency = Duration.zero,
    this.statusForConfirm,
  }) {
    for (final d in initial) {
      _days[d.date] = d.status;
    }
  }

  /// How long every call takes.
  Duration latency;

  /// Which status new days get when they are confirmed.
  WorkStatus Function()? statusForConfirm;

  /// When set, every call throws it (to try the failure path).
  Object? error;

  final Map<DateTime, WorkStatus> _days = {};

  /// How many times [loadConfirmed] was called, and with which windows.
  final List<(DateTime, DateTime)> loadCalls = [];

  /// The days of every [confirm] call.
  final List<List<DateTime>> confirmCalls = [];

  /// What is confirmed now.
  Map<DateTime, WorkStatus> get days => Map.unmodifiable(_days);

  /// Confirms days behind the picker's back, like another device would.
  void put(DateTime date, WorkStatus status) {
    _days[DateTime(date.year, date.month, date.day)] = status;
  }

  @override
  Future<List<ConfirmedDay>> loadConfirmed(DateTime from, DateTime to) async {
    loadCalls.add((from, to));
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (error != null) throw error!;
    return [
      for (final e in _days.entries)
        if (!e.key.isBefore(from) && !e.key.isAfter(to))
          ConfirmedDay(e.key, e.value),
    ];
  }

  @override
  Future<List<ConfirmedDay>> confirm(List<DateTime> days) async {
    confirmCalls.add(List.of(days));
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (error != null) throw error!;
    final status = statusForConfirm?.call() ?? WorkStatus.onsite;
    final saved = [for (final d in days) ConfirmedDay(d, status)];
    for (final d in saved) {
      _days[d.date] = d.status;
    }
    return saved;
  }
}

/// The colours of the default look. Every field has a default, so the picker
/// needs no theme; pass one to change a few colours.
@immutable
class RangePickerTheme {
  const RangePickerTheme({
    this.onsiteColor = const Color(0xFFC45C16),
    this.offsiteColor = const Color(0xFF1F5F99),
    this.ringColor = const Color(0xFF0F6B5C),
    this.rangeStartFill = const Color(0xFF1B5E20),
    this.rangeEndFill = const Color(0xFF2E7D32),
    this.rangeFill = const Color(0xFFDDF1E0),
    this.confirmedFill = const Color(0xFFFFDCCB),
    this.confirmedText = const Color(0xFFD9772B),
    this.skippedFill = const Color(0xFFEDEDED),
    this.skippedText = Colors.black38,
    this.dayText = Colors.black87,
    this.restDayText = Colors.black45,
    this.onRangeEnds = Colors.white,
    this.guideColor = const Color(0xFF5B6770),
    this.cardFill = const Color(0xFFF7F8FA),
    this.cardBorder = const Color(0xFFD6DCE5),
    this.dividerColor = const Color(0xFFE4E4E4),
  });

  /// The dot of an Onsite day.
  final Color onsiteColor;

  /// The dot of an Offsite day.
  final Color offsiteColor;

  /// The ring around the day being looked at, and the ticked boxes.
  final Color ringColor;

  /// First day of the range.
  final Color rangeStartFill;

  /// Last day of the range.
  final Color rangeEndFill;

  /// Days between the first and the last day of the range.
  final Color rangeFill;

  /// A confirmed day inside the range (striped).
  final Color confirmedFill;

  /// The number of that day.
  final Color confirmedText;

  /// A rest day that is skipped (striped).
  final Color skippedFill;

  /// The number of that day.
  final Color skippedText;

  /// The number of an ordinary day.
  final Color dayText;

  /// The number of a rest day.
  final Color restDayText;

  /// The number on the first and last day of the range.
  final Color onRangeEnds;

  /// The "Hướng dẫn" row and its icons.
  final Color guideColor;

  /// Background of the "Cài đặt lịch" card.
  final Color cardFill;

  /// Border of the "Cài đặt lịch" card.
  final Color cardBorder;

  /// The line above the "Hướng dẫn" row.
  final Color dividerColor;
}

/// The labels of the default look (Vietnamese by default).
@immutable
class RangePickerLabels {
  const RangePickerLabels({
    this.guide = 'Hướng dẫn',
    this.settings = 'Cài đặt lịch',
    this.saturdayRest = 'Thứ 7 là ngày nghỉ',
    this.sundayRest = 'Chủ nhật là ngày nghỉ',
    this.onsite = 'Onsite',
    this.offsite = 'Offsite',
    this.confirmedLegend = 'Đã chấm',
    this.skippedLegend = 'Bỏ qua',
    this.cancelButton = 'Hủy',
    this.confirmButton = 'Xác nhận PCCT',
  });

  /// The title of the row that opens the legend.
  final String guide;

  /// The title of the settings card (and the gear's tooltip).
  final String settings;

  /// Checkbox: Saturday is a rest day.
  final String saturdayRest;

  /// Checkbox: Sunday is a rest day.
  final String sundayRest;

  /// Legend: Onsite dot.
  final String onsite;

  /// Legend: Offsite dot.
  final String offsite;

  /// Legend: confirmed day inside the range.
  final String confirmedLegend;

  /// Legend: skipped rest day.
  final String skippedLegend;

  /// The button that cancels the range.
  final String cancelButton;

  /// The button that confirms the valid days.
  final String confirmButton;
}
