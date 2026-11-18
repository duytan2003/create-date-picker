import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int _keyOf(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// One timesheet period ("kỳ"): from day [startDay] of the previous month to
/// the day before it in the next month, e.g. 26/10 → 25/11 for `startDay: 26`.
///
/// A cycle is named after the month it ends in (26/10 → 25/11 is "Tháng 11").
/// With `startDay: 1` the cycle is simply the calendar month.
@immutable
class DatePickerCycle {
  const DatePickerCycle._(this.year, this.month, this.startDay);

  /// The cycle that contains [date].
  factory DatePickerCycle.containing(DateTime date, {int startDay = 26}) {
    assert(startDay >= 1 && startDay <= 28, 'startDay must be 1..28');
    final endMonth =
        startDay != 1 && date.day >= startDay
            ? DateTime(date.year, date.month + 1)
            : DateTime(date.year, date.month);
    return DatePickerCycle._(endMonth.year, endMonth.month, startDay);
  }

  /// Year of the month the cycle ends in.
  final int year;

  /// Month (1..12) the cycle ends in. This is the month that names the cycle.
  final int month;

  /// The day of the month on which a cycle starts.
  final int startDay;

  /// First day of the cycle.
  DateTime get start =>
      startDay == 1
          ? DateTime(year, month, 1)
          : DateTime(year, month - 1, startDay);

  /// Last day of the cycle.
  DateTime get end =>
      startDay == 1
          ? DateTime(year, month + 1, 0)
          : DateTime(year, month, startDay - 1);

  /// The cycle right after this one.
  DatePickerCycle get next {
    final m = DateTime(year, month + 1);
    return DatePickerCycle._(m.year, m.month, startDay);
  }

  /// The cycle right before this one.
  DatePickerCycle get previous {
    final m = DateTime(year, month - 1);
    return DatePickerCycle._(m.year, m.month, startDay);
  }

  /// Whether [date] (time of day ignored) lies inside this cycle.
  bool contains(DateTime date) {
    final k = _keyOf(date);
    return k >= _keyOf(start) && k <= _keyOf(end);
  }

  @override
  bool operator ==(Object other) =>
      other is DatePickerCycle &&
      other.year == year &&
      other.month == month &&
      other.startDay == startDay;

  @override
  int get hashCode => Object.hash(year, month, startDay);

  @override
  String toString() => 'DatePickerCycle($year-$month, from day $startDay)';
}

/// Why a long press could not start a range.
enum RangeStartRejectReason {
  /// The day is outside the cycle that can be confirmed: not in the cycle
  /// being shown, or the cycle being shown is not the one that contains today
  /// (an old cycle reached with the arrows, unless it is still open through
  /// `previousCycleGraceDays`).
  outsideCycle,

  /// The day is after today.
  future,

  /// The day is already confirmed.
  confirmed,

  /// A range must start on the earliest day that is not confirmed yet (the
  /// day right after the last confirmed working day of the cycle).
  notEarliest,
}

/// The texts the picker shows (as a message that slides up from the bottom
/// for a few seconds) when the user presses a day that can not be used.
@immutable
class RangePickerMessages {
  const RangePickerMessages({
    this.confirmedDay =
        'Ngày đã xác nhận - Vui lòng chọn ngày chưa xác nhận xa nhất để bắt đầu',
    this.outsideCycle = 'Ngày ngoài kỳ - Không thể xác nhận',
    this.notEarliest =
        'Các ngày phải xác nhận liên tiếp, không được xen kẽ - Vui lòng chọn lại ngày',
    this.futureDay = 'Ngày này chưa thể xác nhận - Vui lòng chọn ngày khác',
  });

  /// Long press on a day of the cycle that is already confirmed.
  final String confirmedDay;

  /// Long press on a day outside the cycle on screen.
  final String outsideCycle;

  /// Long press on a day of the cycle that is not the earliest unconfirmed one.
  final String notEarliest;

  /// Plain tap on a day of the cycle that has not come yet. (A long press on
  /// such a day shows no message.)
  final String futureDay;

  /// The text for a refused start (a long press), or `null` when there is
  /// none: a day that has not come is only announced on a plain tap.
  String? forReason(RangeStartRejectReason reason) => switch (reason) {
    RangeStartRejectReason.confirmed => confirmedDay,
    RangeStartRejectReason.outsideCycle => outsideCycle,
    RangeStartRejectReason.notEarliest => notEarliest,
    RangeStartRejectReason.future => null,
  };
}

/// The range the user has picked.
@immutable
class CreateRangeSelection {
  const CreateRangeSelection({
    required this.start,
    required this.end,
    required this.validDays,
  });

  /// First day that counts. When the day the user long-pressed is a rest day
  /// that was switched to "skipped", this is the next day that counts.
  final DateTime start;

  /// Last day that counts, or `null` while the user has not picked an end yet.
  /// When the end the user picked is a rest day that was switched to
  /// "skipped", this is the last day before it that counts.
  final DateTime? end;

  /// Every day of the range that should be confirmed: no confirmed days, no
  /// skipped rest days. Empty while [end] is `null`.
  final List<DateTime> validDays;

  @override
  String toString() => 'CreateRangeSelection($start → $end, $validDays)';
}

/// Everything the package knows about one day cell. Passed to
/// [CreateRangeDatePicker.dayCellBuilder]; the package handles the taps, the
/// builder only has to draw.
@immutable
class RangeDayCellInfo {
  const RangeDayCellInfo({
    required this.date,
    required this.inCycle,
    required this.isFuture,
    required this.isToday,
    required this.isRestDay,
    required this.isConfirmed,
    required this.isViewed,
    this.isRangeStart = false,
    this.isRangeEnd = false,
    this.isInRange = false,
    this.isSkipped = false,
    this.isLocked = false,
    this.isNextCycleDay = false,
  });

  /// The day (time of day is always midnight).
  final DateTime date;

  /// `false` for the faded days of the neighbouring cycles that only fill the
  /// first and last week of the grid.
  final bool inCycle;

  /// After today. Such days can not be tapped.
  final bool isFuture;

  /// Today.
  final bool isToday;

  /// Falls on a weekday the user marked as a rest day.
  final bool isRestDay;

  /// Already confirmed ("Đã Xác nhận PCCT"), taken from `confirmedDates`.
  final bool isConfirmed;

  /// The day whose information is currently shown (the one with the ring).
  final bool isViewed;

  /// The first day that counts in the range (the dark green cell).
  final bool isRangeStart;

  /// The last day of the range that counts. When the end is a rest day that
  /// was switched off, this is the last day before it that counts.
  final bool isRangeEnd;

  /// Lies between the day the user long-pressed and the end (both included).
  /// Skipped and locked days inside the range are also `true` here.
  final bool isInRange;

  /// A rest day inside the range that does not count ("CN bỏ qua"). Tapping it
  /// makes it count.
  final bool isSkipped;

  /// A confirmed day inside the range: it never counts and can not be toggled.
  final bool isLocked;

  /// A day of the *next* cycle that fills the last week of the grid (after
  /// the last day of the cycle on screen). Once that day has come (today or
  /// earlier) it can be tapped to look at it, so the app can still work on the
  /// old cycle on the 26th while looking at the day the new cycle started.
  /// It is never part of a range of the cycle on screen.
  final bool isNextCycleDay;

  /// Whether a tap on this cell does anything: a day of the cycle, or a day
  /// of the next cycle that has already come, and never a day in the future.
  bool get isTappable => (inCycle || isNextCycleDay) && !isFuture;
}

/// The pieces of the picker, handed to [CreateRangeDatePicker.builder] so the
/// screen can place them anywhere.
class CreateRangeDatePickerParts {
  const CreateRangeDatePickerParts({
    required this.cycle,
    required this.title,
    required this.leftArrow,
    required this.rightArrow,
    required this.weekdayRow,
    required this.grid,
    required this.settingsButton,
    required this.restWeekdays,
    required this.setRestWeekday,
    required this.selection,
    required this.viewedDate,
    required this.cancelRange,
  });

  /// The cycle being shown.
  final DatePickerCycle cycle;

  /// The range being picked, or `null` when there is none.
  final CreateRangeSelection? selection;

  /// The day whose information is shown (the one with the ring), if any.
  final DateTime? viewedDate;

  /// Cancels the range. Wire it to the "Hủy" button. Does nothing when there
  /// is no range.
  final VoidCallback cancelRange;

  /// "Tháng 11 · 2025".
  final Widget title;

  /// Goes to the previous cycle.
  final Widget leftArrow;

  /// Goes to the next cycle.
  final Widget rightArrow;

  /// T2 … CN.
  final Widget weekdayRow;

  /// The day cells.
  final Widget grid;

  /// The gear that opens the rest-day settings (two checkboxes).
  final Widget settingsButton;

  /// The weekdays that are rest days right now (`DateTime.saturday`, ...).
  /// Use it with [setRestWeekday] to draw your own settings UI instead of
  /// [settingsButton].
  final Set<int> restWeekdays;

  /// Marks [weekday] as a rest day (or not). Same effect as the checkboxes of
  /// [settingsButton]: it cancels the range and calls
  /// `onRestWeekdaysChanged`.
  final void Function(int weekday, bool isRestDay) setRestWeekday;
}

/// Lets the screen read or cancel the range from outside the picker.
class CreateRangeDatePickerController {
  _CreateRangeDatePickerState? _state;

  /// Whether a range (with or without an end) is being picked.
  bool get hasRange => _state?._anchor != null;

  /// The range being picked, or `null`.
  CreateRangeSelection? get selection => _state?._selection();

  /// Cancels the range and calls `onRangeCancelled`. Does nothing when there
  /// is no range.
  void cancelRange() => _state?._cancelRange();
}

/// A calendar for timesheets ("chấm công"): it shows one cycle at a time
/// (26 of last month → 25 of this month), lets the user pick rest days, tap a
/// day to look at it, and pick a from–to range of days to confirm.
///
/// ## Picking a range
///
/// * Long-press (0.5 s by default) the earliest day that is not confirmed yet
///   to start a range. Only the cycle that contains today can be confirmed
///   (plus the cycle right before it for [previousCycleGraceDays] days):
///   in any other cycle (an old one reached with the arrows) every long press
///   is "outside the cycle". Any other day is refused through
///   [onRangeStartRejected], and a message tells the user why (see
///   [showMessages], [messages] and [messageDuration]).
/// * Then tap a day after it: that is the end. Tap another day to change the
///   end. The end may be a rest day.
/// * Rest days inside the range are skipped. Tap one to make it count, tap
///   again to skip it. A rest day that is the start or the end counts by
///   default; tap it to skip it (the range then starts or ends on the
///   nearest day that counts), tap again to bring it back.
/// * While a range exists, a long press behaves like a tap.
/// * Cancel with [CreateRangeDatePickerController.cancelRange] or
///   [CreateRangeDatePickerParts.cancelRange]. The range is also cancelled
///   when the cycle changes, when the rest days change, or when
///   [confirmedDates] changes.
///
/// This is a separate widget; [CreateDatePicker] is not affected.
class CreateRangeDatePicker extends StatefulWidget {
  const CreateRangeDatePicker({
    super.key,
    this.cycleStartDay = 26,
    this.previousCycleGraceDays = 1,
    this.controller,
    this.onRangeChanged,
    this.onRangeCancelled,
    this.onRangeStartRejected,
    this.showMessages = true,
    this.messages = const RangePickerMessages(),
    this.messageDuration = const Duration(seconds: 5),
    this.longPressDuration = const Duration(milliseconds: 500),
    this.initialDate,
    this.today,
    this.confirmedDates = const {},
    this.initialRestWeekdays = const {DateTime.sunday},
    this.onRestWeekdaysChanged,
    this.onDateTap,
    this.onCycleChanged,
    this.width,
    this.cellHeight = 44,
    this.weekdayLabels = const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'],
    this.monthLabels = const [
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12',
    ],
    this.saturdayRestLabel = 'T7 là ngày nghỉ',
    this.sundayRestLabel = 'CN là ngày nghỉ',
    this.settingsIcon,
    this.builder,
    this.titleBuilder,
    this.leftArrowBuilder,
    this.rightArrowBuilder,
    this.weekdayCellBuilder,
    this.dayCellBuilder,
  }) : assert(
         cycleStartDay >= 1 && cycleStartDay <= 28,
         'cycleStartDay must be between 1 and 28',
       ),
       assert(
         previousCycleGraceDays >= 0,
         'previousCycleGraceDays can not be negative',
       ),
       assert(weekdayLabels.length == 7, 'weekdayLabels needs 7 items'),
       assert(monthLabels.length == 12, 'monthLabels needs 12 items');

  /// Day of the month on which a cycle starts (default 26, so a cycle runs
  /// 26 → 25). Allowed values 1..28.
  final int cycleStartDay;

  /// Only the cycle that contains today can be confirmed (a long press in any
  /// other cycle is "outside the cycle"), plus the cycle right *before* it
  /// during the first N days of the current cycle, the first day counting as
  /// day 1. Example: 5 with cycles starting on the 26th keeps the cycle
  /// 26/10 → 25/11 open from 26/11 to 30/11.
  ///
  /// Default 1: the previous cycle stays open on the first day of the new one
  /// (the 26th). The app chooses its own N by passing a number; 0 closes the
  /// previous cycle from the first day.
  final int previousCycleGraceDays;

  /// Reads or cancels the range from outside.
  final CreateRangeDatePickerController? controller;

  /// Called every time the range changes: when it starts (`end` is `null` and
  /// `validDays` is empty), when the end changes, and when a rest day is
  /// switched on or off. `start` and `end` are the first and last day that
  /// count; `validDays` are the days to confirm.
  final void Function(DateTime start, DateTime? end, List<DateTime> validDays)?
  onRangeChanged;

  /// Called when the range is cancelled, whatever the reason.
  final VoidCallback? onRangeCancelled;

  /// Called when a long press can not start a range, with the reason.
  final void Function(DateTime date, RangeStartRejectReason reason)?
  onRangeStartRejected;

  /// Whether the picker itself tells the user why a press was refused, with a
  /// message that slides up from the bottom (a `SnackBar`, so it needs a
  /// `Scaffold`/`MaterialApp` above the picker). Default `true`. Turn it off
  /// to show your own message from [onRangeStartRejected].
  final bool showMessages;

  /// The texts of those messages (Vietnamese by default).
  final RangePickerMessages messages;

  /// How long a message stays. Default 5 seconds.
  final Duration messageDuration;

  /// How long a day must be pressed to start a range. Default 0.5 s.
  final Duration longPressDuration;

  /// Opens on the cycle that contains this date. Defaults to today.
  final DateTime? initialDate;

  /// Overrides "today" (default `DateTime.now()`). Mostly for tests and demos.
  final DateTime? today;

  /// Days that are already confirmed. They can be tapped to see their
  /// information but never become part of a range.
  final Set<DateTime> confirmedDates;

  /// Weekdays (`DateTime.saturday`, `DateTime.sunday`, …) that are rest days
  /// when the picker opens. The user changes them with the gear; the screen
  /// stores the result (see [onRestWeekdaysChanged]) and passes it back here
  /// the next time. Default: Sunday only.
  final Set<int> initialRestWeekdays;

  /// Called when the user changes the rest days in the settings popup.
  final ValueChanged<Set<int>>? onRestWeekdaysChanged;

  /// Called when the user taps a day to see its information. The tapped day
  /// also gets a ring that stays until another day is tapped. This includes a
  /// day of the next cycle that has already come (see
  /// [RangeDayCellInfo.isNextCycleDay]).
  final ValueChanged<DateTime>? onDateTap;

  /// Called after the user moves to another cycle with the arrows.
  final void Function(DateTime start, DateTime end)? onCycleChanged;

  /// Width of the picker. Unbounded when `null`.
  final double? width;

  /// Height of every day cell.
  final double cellHeight;

  /// Monday first: T2, T3, T4, T5, T6, T7, CN.
  final List<String> weekdayLabels;

  /// 12 month names used in the title.
  final List<String> monthLabels;

  /// Label of the Saturday checkbox in the settings popup.
  final String saturdayRestLabel;

  /// Label of the Sunday checkbox in the settings popup.
  final String sundayRestLabel;

  /// Icon of the settings button (default: a small gear).
  final Widget? settingsIcon;

  /// Places every part of the picker. When `null` a simple default layout is
  /// used.
  final Widget Function(BuildContext context, CreateRangeDatePickerParts parts)?
  builder;

  /// Custom title. Receives the cycle being shown.
  final Widget Function(BuildContext context, DatePickerCycle cycle)?
  titleBuilder;

  /// Custom "previous cycle" arrow. Call [onTap] when pressed.
  final Widget Function(BuildContext context, VoidCallback onTap)?
  leftArrowBuilder;

  /// Custom "next cycle" arrow. Call [onTap] when pressed.
  final Widget Function(BuildContext context, VoidCallback onTap)?
  rightArrowBuilder;

  /// Custom weekday header cell. `weekday` follows `DateTime.monday` …
  /// `DateTime.sunday`.
  final Widget Function(
    BuildContext context,
    int weekday,
    String label,
    bool isRestDay,
  )?
  weekdayCellBuilder;

  /// Draws one day. The package handles taps; this only has to look right.
  final Widget Function(BuildContext context, RangeDayCellInfo info)?
  dayCellBuilder;

  @override
  State<CreateRangeDatePicker> createState() => _CreateRangeDatePickerState();
}

class _CreateRangeDatePickerState extends State<CreateRangeDatePicker> {
  late DatePickerCycle _cycle;
  late Set<int> _restWeekdays;
  late Set<int> _confirmedKeys;
  DateTime? _viewed;

  // The range. `_anchor` is the day that was long-pressed (always the
  // earliest allowed start); everything else is derived from it.
  DateTime? _anchor;
  DateTime? _end;

  /// Rest days inside the range that were switched on (they count).
  final Set<int> _included = {};

  /// The anchor is a rest day and the user switched it off.
  bool _anchorSkipped = false;

  /// The end is a rest day and the user switched it off.
  bool _endSkipped = false;

  /// First and last counted day of the range, recomputed on every build.
  DateTime? _effectiveStart;
  DateTime? _effectiveEnd;

  @override
  void initState() {
    super.initState();
    final initial = _dateOnly(widget.initialDate ?? _today);
    _cycle = DatePickerCycle.containing(
      initial,
      startDay: widget.cycleStartDay,
    );
    _restWeekdays = {...widget.initialRestWeekdays};
    _confirmedKeys = _keysOf(widget.confirmedDates);
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(covariant CreateRangeDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
    final keys = _keysOf(widget.confirmedDates);
    final changed =
        keys.length != _confirmedKeys.length ||
        !keys.containsAll(_confirmedKeys);
    _confirmedKeys = keys;
    if (changed && _anchor != null) {
      // The data the range was built on is gone. This runs while the parent is
      // building, so the callback has to wait for the frame to end.
      _clearRange();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRangeCancelled?.call();
      });
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  Set<int> _keysOf(Set<DateTime> dates) => {for (final d in dates) _keyOf(d)};

  DateTime get _today => _dateOnly(widget.today ?? DateTime.now());

  // ---------------------------------------------------------------- facts

  bool _isRest(DateTime d) => _restWeekdays.contains(d.weekday);

  bool _isConfirmed(DateTime d) => _confirmedKeys.contains(_keyOf(d));

  bool _isFuture(DateTime d) => _keyOf(d) > _keyOf(_today);

  DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// The only day a range may start on: the day after the last confirmed
  /// working day of the cycle (the cycle's first day when nothing is
  /// confirmed), skipping confirmed days. `null` when nothing is left.
  DateTime? _earliestStart() {
    final first = _cycle.start;
    final last = _cycle.end;
    DateTime? lastConfirmedWorking;
    for (var d = first; _keyOf(d) <= _keyOf(last); d = _addDays(d, 1)) {
      if (_isConfirmed(d) && !_isRest(d)) lastConfirmedWorking = d;
    }
    var s =
        lastConfirmedWorking == null
            ? first
            : _addDays(lastConfirmedWorking, 1);
    while (_keyOf(s) <= _keyOf(last) && _isConfirmed(s)) {
      s = _addDays(s, 1);
    }
    return _keyOf(s) <= _keyOf(last) ? s : null;
  }

  /// Whether [d] (somewhere in the range) counts towards the range.
  bool _counts(DateTime d) {
    if (_isConfirmed(d)) return false;
    if (!_isRest(d)) return true;
    if (_anchor != null && _keyOf(d) == _keyOf(_anchor!)) {
      return !_anchorSkipped;
    }
    if (_end != null && _keyOf(d) == _keyOf(_end!)) return !_endSkipped;
    return _included.contains(_keyOf(d));
  }

  /// First day that counts, from the anchor on. Without an end this is the
  /// anchor, or - when the anchor was switched off - the next day that is in
  /// the cycle, not in the future and counts.
  DateTime? _computeEffectiveStart() {
    final anchor = _anchor;
    if (anchor == null) return null;
    final limit = _end ?? _cycle.end;
    for (
      var d = anchor;
      _keyOf(d) <= _keyOf(limit) && !_isFuture(d);
      d = _addDays(d, 1)
    ) {
      if (_counts(d)) return d;
    }
    return null;
  }

  /// Last day that counts, looking back from the end the user picked: the end
  /// itself, or - when it is a rest day that was switched off - the day before
  /// it that counts. `null` while there is no end.
  DateTime? _computeEffectiveEnd() {
    final end = _end;
    final anchor = _anchor;
    if (end == null || anchor == null) return null;
    for (var d = end; _keyOf(d) >= _keyOf(anchor); d = _addDays(d, -1)) {
      if (_counts(d)) return d;
    }
    return null;
  }

  List<DateTime> _validDays(DateTime start, DateTime end) {
    final days = <DateTime>[];
    for (var d = start; _keyOf(d) <= _keyOf(end); d = _addDays(d, 1)) {
      if (_counts(d)) days.add(d);
    }
    return days;
  }

  CreateRangeSelection? _selection() {
    final start = _computeEffectiveStart();
    if (_anchor == null || start == null) return null;
    final end = _computeEffectiveEnd();
    // An end was picked but nothing counts any more.
    if (_end != null && end == null) return null;
    return CreateRangeSelection(
      start: start,
      end: end,
      validDays: end == null ? const [] : _validDays(start, end),
    );
  }

  RangeDayCellInfo _infoFor(DateTime date) {
    final today = _today;
    final key = _keyOf(date);
    final anchor = _anchor;
    final inSpan =
        anchor != null &&
        key >= _keyOf(anchor) &&
        key <= _keyOf(_end ?? anchor);
    final confirmed = _isConfirmed(date);
    final rest = _isRest(date);
    return RangeDayCellInfo(
      date: date,
      inCycle: _cycle.contains(date),
      isFuture: key > _keyOf(today),
      isToday: key == _keyOf(today),
      isRestDay: rest,
      isConfirmed: confirmed,
      isViewed: _viewed != null && _keyOf(_viewed!) == key,
      isRangeStart: _effectiveStart != null && _keyOf(_effectiveStart!) == key,
      isRangeEnd: _effectiveEnd != null && _keyOf(_effectiveEnd!) == key,
      isInRange: inSpan,
      isLocked: inSpan && confirmed,
      isSkipped: inSpan && !confirmed && rest && !_counts(date),
      isNextCycleDay: key > _keyOf(_cycle.end),
    );
  }

  // -------------------------------------------------------------- actions

  void _goToCycle(DatePickerCycle cycle) {
    final hadRange = _anchor != null;
    setState(() {
      _clearRange();
      _cycle = cycle;
      _viewed = null;
    });
    if (hadRange) widget.onRangeCancelled?.call();
    widget.onCycleChanged?.call(cycle.start, cycle.end);
  }

  void _clearRange() {
    _anchor = null;
    _end = null;
    _anchorSkipped = false;
    _endSkipped = false;
    _included.clear();
  }

  void _cancelRange() {
    if (_anchor == null) return;
    setState(_clearRange);
    widget.onRangeCancelled?.call();
  }

  void _notifyRange() {
    final selection = _selection();
    if (selection == null) {
      // Nothing left that could count (e.g. the start was switched off and
      // there is no working day after it).
      _cancelRange();
      return;
    }
    widget.onRangeChanged?.call(
      selection.start,
      selection.end,
      selection.validDays,
    );
  }

  /// Whether a range may be started in [cycle]: the cycle that contains
  /// today, or the one right before it during the first
  /// `previousCycleGraceDays` days of the current cycle (its first day is day
  /// 1).
  bool _isConfirmableCycle(DatePickerCycle cycle) {
    final current = DatePickerCycle.containing(
      _today,
      startDay: widget.cycleStartDay,
    );
    if (cycle == current) return true;
    if (widget.previousCycleGraceDays > 0 && cycle == current.previous) {
      final start = current.start;
      final dayOfCycle =
          DateTime.utc(_today.year, _today.month, _today.day)
              .difference(DateTime.utc(start.year, start.month, start.day))
              .inDays +
          1;
      return dayOfCycle <= widget.previousCycleGraceDays;
    }
    return false;
  }

  void _showMessage(String text) {
    if (!widget.showMessages) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: widget.messageDuration),
      );
  }

  void _onTap(DateTime date, {bool messageForFutureDay = true}) {
    final info = _infoFor(date);
    if (!info.isTappable) {
      // A plain tap on a day of the cycle that has not come yet: say so.
      if (messageForFutureDay && info.inCycle && info.isFuture) {
        _showMessage(widget.messages.futureDay);
      }
      return;
    }
    // A day of the next cycle is only ever looked at; it never touches the
    // range of the cycle on screen.
    if (_anchor == null || info.isNextCycleDay) {
      _view(date);
    } else {
      _tapWithRange(date);
    }
  }

  void _tapWithRange(DateTime date) {
    final key = _keyOf(date);
    final anchor = _anchor!;

    // Confirmed days can only be looked at; the range stays as it is.
    if (_isConfirmed(date)) {
      _view(date);
      return;
    }

    if (key == _keyOf(anchor)) {
      if (_isRest(date)) {
        // A rest day start: switch it off, or back on.
        setState(() => _anchorSkipped = !_anchorSkipped);
        _notifyRange();
      } else {
        _cancelRange();
      }
      return;
    }

    if (_end != null && key == _keyOf(_end!)) {
      if (_isRest(date)) {
        // A rest day end: switch it off, or back on. While it is off the
        // range ends on the last day before it that counts.
        setState(() => _endSkipped = !_endSkipped);
        _notifyRange();
      }
      return;
    }

    if (_effectiveStart != null &&
        key == _keyOf(_effectiveStart!) &&
        !_isRest(date)) {
      // The start moved here because the long-pressed rest day was switched
      // off: tapping the start cancels, like for any working day start.
      _cancelRange();
      return;
    }

    if (key < _keyOf(anchor)) {
      _view(date);
      return;
    }

    if (_isRest(date) && _end != null && key < _keyOf(_end!)) {
      // A rest day inside the range: make it count, or skip it again.
      setState(() {
        if (!_included.remove(key)) _included.add(key);
      });
      _notifyRange();
      return;
    }

    // Any other day after the start is the new end, a rest day included (it
    // counts, until the user taps it again).
    setState(() {
      _end = date;
      _endSkipped = false;
      // Rest days switched on beyond the new end are no longer in the range.
      _included.removeWhere((k) => k >= key);
    });
    _notifyRange();
  }

  void _onLongPress(DateTime date) {
    if (_anchor != null) {
      // Works like a tap, except that it does not announce a day that has not
      // come: that message is for a plain tap only.
      _onTap(date, messageForFutureDay: false);
      return;
    }
    final info = _infoFor(date);
    RangeStartRejectReason? reason;
    final earliest = _earliestStart();
    // Only the cycle that contains today (and the one right before it for
    // `previousCycleGraceDays` days) can be confirmed. Any other cycle,
    // reached with the arrows, counts as "outside".
    if (!info.inCycle || !_isConfirmableCycle(_cycle)) {
      reason = RangeStartRejectReason.outsideCycle;
    } else if (info.isFuture) {
      reason = RangeStartRejectReason.future;
    } else if (info.isConfirmed) {
      reason = RangeStartRejectReason.confirmed;
    } else if (earliest == null || _keyOf(earliest) != _keyOf(date)) {
      reason = RangeStartRejectReason.notEarliest;
    }
    if (reason != null) {
      final text = widget.messages.forReason(reason);
      if (text != null) _showMessage(text);
      widget.onRangeStartRejected?.call(date, reason);
      return;
    }
    setState(() {
      _anchor = date;
      _end = null;
      _anchorSkipped = false;
      _endSkipped = false;
      _included.clear();
    });
    _notifyRange();
  }

  void _view(DateTime date) {
    setState(() => _viewed = date);
    widget.onDateTap?.call(date);
  }

  void _setRestWeekday(int weekday, bool isRest) {
    final hadRange = _anchor != null;
    setState(() {
      if (isRest) {
        _restWeekdays.add(weekday);
      } else {
        _restWeekdays.remove(weekday);
      }
      _clearRange();
    });
    if (hadRange) widget.onRangeCancelled?.call();
    widget.onRestWeekdaysChanged?.call(Set.unmodifiable(_restWeekdays));
  }

  // ---------------------------------------------------------------- parts

  Widget _buildTitle(BuildContext context) {
    if (widget.titleBuilder != null) {
      return widget.titleBuilder!(context, _cycle);
    }
    return Text(
      '${widget.monthLabels[_cycle.month - 1]} · ${_cycle.year}',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildArrow(
    BuildContext context, {
    required bool left,
    required VoidCallback onTap,
  }) {
    final builder = left ? widget.leftArrowBuilder : widget.rightArrowBuilder;
    if (builder != null) return builder(context, onTap);
    return IconButton(
      key: ValueKey(left ? 'rdp-left' : 'rdp-right'),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
    );
  }

  Widget _buildWeekdayRow(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _buildWeekdayCell(context, i + 1, widget.weekdayLabels[i]),
          ),
      ],
    );
  }

  Widget _buildWeekdayCell(BuildContext context, int weekday, String label) {
    final isRest = _restWeekdays.contains(weekday);
    if (widget.weekdayCellBuilder != null) {
      return widget.weekdayCellBuilder!(context, weekday, label, isRest);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Opacity(
          opacity: isRest ? 0.4 : 1,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final start = _cycle.start;
    final end = _cycle.end;
    final first = DateTime(
      start.year,
      start.month,
      start.day - (start.weekday - 1),
    );
    final last = DateTime(
      end.year,
      end.month,
      end.day + (DateTime.sunday - end.weekday),
    );
    final dayCount =
        DateTime.utc(
          last.year,
          last.month,
          last.day,
        ).difference(DateTime.utc(first.year, first.month, first.day)).inDays +
        1;

    final rows = <Widget>[];
    for (var week = 0; week < dayCount ~/ 7; week++) {
      rows.add(
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _buildCell(
                  context,
                  DateTime(first.year, first.month, first.day + week * 7 + i),
                ),
              ),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _buildCell(BuildContext context, DateTime date) {
    final info = _infoFor(date);
    final content = (widget.dayCellBuilder ?? _defaultDayCell)(context, info);
    return RawGestureDetector(
      key: ValueKey('rdp-day-${date.year}-${date.month}-${date.day}'),
      behavior: HitTestBehavior.opaque,
      gestures: {
        // A day of the cycle that has not come yet also gets the tap: it
        // answers with a message instead of doing anything.
        if (info.isTappable || (info.inCycle && info.isFuture))
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(),
                (TapGestureRecognizer instance) =>
                    instance.onTap = () => _onTap(date),
              ),
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
          LongPressGestureRecognizer
        >(
          () => LongPressGestureRecognizer(duration: widget.longPressDuration),
          (LongPressGestureRecognizer instance) =>
              instance.onLongPress = () => _onLongPress(date),
        ),
      },
      child: SizedBox(height: widget.cellHeight, child: content),
    );
  }

  Widget _defaultDayCell(BuildContext context, RangeDayCellInfo info) {
    final scheme = Theme.of(context).colorScheme;
    final faded = !info.isTappable;
    Color textColor = scheme.onSurface;
    if (info.isRestDay) textColor = scheme.onSurface.withValues(alpha: 0.55);
    if (info.isConfirmed) textColor = scheme.onSurface.withValues(alpha: 0.5);
    if (info.isSkipped) textColor = scheme.onSurface.withValues(alpha: 0.35);

    Color? fill;
    if (info.isRangeStart) {
      fill = const Color(0xFF1B5E20); // dark green
      textColor = Colors.white;
    } else if (info.isRangeEnd) {
      fill = const Color(0xFF2E7D32);
      textColor = Colors.white;
    } else if (info.isLocked) {
      fill = const Color(0xFFFFE0B2); // confirmed day inside the range
    } else if (info.isInRange && !info.isSkipped) {
      fill = const Color(0xFFDDF1E0);
    }

    return Center(
      child: Opacity(
        opacity: faded ? 0.35 : 1,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border:
                info.isViewed
                    ? Border.all(color: const Color(0xFF0F6B5C), width: 1)
                    : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${info.date.day}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: info.isToday ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
              if (info.isConfirmed)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Icon(Icons.check, size: 9, color: textColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return PopupMenuButton<void>(
      key: const ValueKey('rdp-settings'),
      tooltip: '',
      padding: EdgeInsets.zero,
      icon:
          widget.settingsIcon ?? const Icon(Icons.settings_outlined, size: 18),
      itemBuilder:
          (context) => [
            PopupMenuItem<void>(
              enabled: false,
              padding: EdgeInsets.zero,
              child: StatefulBuilder(
                builder:
                    (context, setInner) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _restCheckbox(
                          key: const ValueKey('rdp-rest-saturday'),
                          label: widget.saturdayRestLabel,
                          weekday: DateTime.saturday,
                          setInner: setInner,
                        ),
                        _restCheckbox(
                          key: const ValueKey('rdp-rest-sunday'),
                          label: widget.sundayRestLabel,
                          weekday: DateTime.sunday,
                          setInner: setInner,
                        ),
                      ],
                    ),
              ),
            ),
          ],
    );
  }

  Widget _restCheckbox({
    required Key key,
    required String label,
    required int weekday,
    required StateSetter setInner,
  }) {
    final checked = _restWeekdays.contains(weekday);
    return InkWell(
      key: key,
      onTap: () {
        _setRestWeekday(weekday, !checked);
        setInner(() {});
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IgnorePointer(child: Checkbox(value: checked, onChanged: (_) {})),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _effectiveStart = _computeEffectiveStart();
    _effectiveEnd = _computeEffectiveEnd();
    final parts = CreateRangeDatePickerParts(
      selection: _selection(),
      viewedDate: _viewed,
      cancelRange: _cancelRange,
      restWeekdays: Set.unmodifiable(_restWeekdays),
      setRestWeekday: _setRestWeekday,
      cycle: _cycle,
      title: _buildTitle(context),
      leftArrow: _buildArrow(
        context,
        left: true,
        onTap: () => _goToCycle(_cycle.previous),
      ),
      rightArrow: _buildArrow(
        context,
        left: false,
        onTap: () => _goToCycle(_cycle.next),
      ),
      weekdayRow: _buildWeekdayRow(context),
      grid: _buildGrid(context),
      settingsButton: _buildSettingsButton(context),
    );

    final body =
        widget.builder != null
            ? widget.builder!(context, parts)
            : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    parts.leftArrow,
                    Expanded(child: Center(child: parts.title)),
                    parts.rightArrow,
                    parts.settingsButton,
                  ],
                ),
                parts.weekdayRow,
                parts.grid,
              ],
            );

    return SizedBox(width: widget.width, child: body);
  }
}
