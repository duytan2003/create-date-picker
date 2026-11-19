import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'range_picker_default_ui.dart';
import 'range_picker_models.dart';

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
    this.status,
  });

  /// How the day was worked, for a confirmed day that came from the
  /// `repository`; `null` for any other day (and when `confirmedDates` is
  /// used instead of a repository).
  final WorkStatus? status;

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
    required this.isLoading,
    required this.isConfirming,
    required this.canConfirm,
    required this.confirm,
  });

  /// The confirmed days of the cycle on screen are loading (by the repository,
  /// or the `isLoading` the screen passed).
  final bool isLoading;

  /// A confirmation is on its way (to the repository, or the `isConfirming`
  /// the screen passed).
  final bool isConfirming;

  /// Whether [confirm] would do something: there is a repository or an
  /// `onConfirm`, a range with at least one valid day, and no confirmation on
  /// its way.
  final bool canConfirm;

  /// Sends the valid days of the range to the repository (or to `onConfirm`).
  /// Wire it to a custom "Xác nhận" button. Completes with `true` when it was
  /// saved (handed over, with `onConfirm`).
  final Future<bool> Function() confirm;

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

/// Lets the screen read, cancel and confirm the range from outside the picker,
/// for example from its own "Hủy" and "Xác nhận PCCT" buttons.
///
/// It tells its listeners (one frame later) whenever [hasRange], [selection],
/// [canConfirm], [isLoading] or [isConfirming] changes, so a button can follow
/// the range with a `ListenableBuilder`:
///
/// ```dart
/// ListenableBuilder(
///   listenable: controller,
///   builder: (context, _) => FilledButton(
///     onPressed: controller.canConfirm ? controller.confirm : null,
///     child: const Text('Xác nhận PCCT'),
///   ),
/// )
/// ```
///
/// Create it once, keep it in a `State` and call [dispose] when the screen is
/// disposed.
class CreateRangeDatePickerController extends ChangeNotifier {
  _CreateRangeDatePickerState? _state;

  void _tell() => notifyListeners();

  /// Whether a range (with or without an end) is being picked.
  bool get hasRange => _state?._anchor != null;

  /// Whether [confirm] would do something right now: there is a repository or
  /// an `onConfirm`, a range with at least one valid day, and no confirmation
  /// on its way.
  bool get canConfirm => _state?._canConfirm ?? false;

  /// The range being picked, or `null`.
  CreateRangeSelection? get selection => _state?._selection();

  /// Cancels the range and calls `onRangeCancelled`. Does nothing when there
  /// is no range.
  void cancelRange() => _state?._cancelRange();

  /// Sends the valid days of the range to the repository (or to `onConfirm`),
  /// like the "Xác nhận" button. Completes with `true` when they were saved
  /// (with `onConfirm`: when they were handed over), `false` when there was
  /// nothing to confirm or it failed.
  Future<bool> confirm() => _state?._confirm() ?? Future.value(false);

  /// Loads the confirmed days of the cycle on screen again.
  ///
  /// With `onVisibleRangeChanged` (no repository) it calls that callback again
  /// for the cycle on screen.
  Future<void> reload() => _state?._reload() ?? Future.value();

  /// The confirmed days are loading (the repository, or the `isLoading` the
  /// screen passed).
  bool get isLoading => _state?._isLoading ?? false;

  /// A confirmation is on its way (the repository, or the `isConfirming` the
  /// screen passed).
  bool get isConfirming => _state?._isConfirming ?? false;
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
///   [onRangeStartRejected] with the reason. The picker shows no message of
///   its own: the app tells the user what it wants (see also
///   [onFutureDayTap], [onLoadFailed] and [onConfirmFailed]).
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
    this.repository,
    this.onConfirmed,
    this.confirmedDays,
    this.isLoading = false,
    this.isConfirming = false,
    this.onVisibleRangeChanged,
    this.onConfirm,
    this.showActionBar,
    this.theme = const RangePickerTheme(),
    this.labels = const RangePickerLabels(),
    this.persistRestWeekdays = true,
    this.restWeekdaysKey = 'create_date_picker.rest_weekdays',
    this.controller,
    this.onRangeChanged,
    this.onRangeCancelled,
    this.onRangeStartRejected,
    this.onFutureDayTap,
    this.onLoadFailed,
    this.onConfirmFailed,
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
       assert(
         repository == null || confirmedDates.length < 1,
         'Give either a repository or confirmedDates, not both',
       ),
       assert(
         repository == null ||
             (confirmedDays == null &&
                 onVisibleRangeChanged == null &&
                 onConfirm == null),
         'Give either a repository or confirmedDays / onVisibleRangeChanged / '
         'onConfirm, not both',
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

  /// Where the data comes from. With a repository the picker does everything
  /// itself: it loads the confirmed days of the cycle on screen (and again
  /// after every change of cycle), draws the Onsite/Offsite dots, and sends
  /// the valid days of the range to [TimesheetRepository.confirm] when the
  /// user presses "Xác nhận PCCT". Give either a repository or
  /// [confirmedDates], not both. Create the repository once and keep it (for
  /// example in `initState`): a different instance makes the picker load
  /// again.
  final TimesheetRepository? repository;

  /// Called after the repository saved a confirmation, with the saved days.
  final ValueChanged<List<ConfirmedDay>>? onConfirmed;

  /// The confirmed days (date + Onsite/Offsite) of the cycle on screen, for an
  /// app that loads the data itself (a Bloc, a provider, ...): the picker only
  /// draws what it is given. Pass the whole list again whenever it changes.
  /// Together with [onVisibleRangeChanged] (to know what to load) and
  /// [onConfirm] (to save). The range is cancelled when the set of days
  /// changes, which is how a successful confirmation clears it. Not together
  /// with a [repository].
  final List<ConfirmedDay>? confirmedDays;

  /// The app is loading the confirmed days: a thin line shows under the grid.
  /// Used without a [repository]; with one the picker knows by itself.
  final bool isLoading;

  /// The app is saving a confirmation: the "Xác nhận PCCT" button shows a
  /// spinner and can not be pressed. Used without a [repository].
  final bool isConfirming;

  /// Called when the picker opens and every time the cycle on screen changes,
  /// with the dates to load: the cycle plus 6 days on each side (the grid shows
  /// whole weeks). Ask your backend for the confirmed days of that window and
  /// pass them back through [confirmedDays]. Not together with a [repository].
  final void Function(DateTime from, DateTime to)? onVisibleRangeChanged;

  /// Called when the user presses "Xác nhận PCCT" (or
  /// `CreateRangeDatePickerController.confirm`), with the days that count
  /// (rest days that were skipped are not in it). Save them, then pass the new
  /// [confirmedDays]. The range stays until the days change, so a failed save
  /// can be tried again. Not together with a [repository].
  final ValueChanged<List<DateTime>>? onConfirm;

  /// Whether the default layout draws the "Hủy" and "Xác nhận PCCT" buttons.
  /// Default (`null`): drawn when there is a [repository] (the package does
  /// everything), not drawn otherwise, so the screen draws its own buttons and
  /// wires them to the [controller] (`cancelRange`, `confirm`, `canConfirm`,
  /// `hasRange`). Pass `true` to get the ready-made buttons next to
  /// [onConfirm]. Has no effect with a custom [builder] (use
  /// `parts.cancelRange` and `parts.confirm`).
  final bool? showActionBar;

  /// The colours of the default look.
  final RangePickerTheme theme;

  /// The texts of the default look (Vietnamese by default).
  final RangePickerLabels labels;

  /// Whether the picker remembers the rest days on the device (with
  /// `shared_preferences`) and restores them the next time it opens. The
  /// stored choice wins over [initialRestWeekdays]. Default `true`.
  final bool persistRestWeekdays;

  /// The key the rest days are stored under. Change it when two pickers in one
  /// app need different settings.
  final String restWeekdaysKey;

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

  /// Called when a long press can not start a range, with the reason. The
  /// picker shows no message itself: the app decides what to tell the user
  /// (a `SnackBar`, a dialog, nothing, ...) for each [RangeStartRejectReason].
  final void Function(DateTime date, RangeStartRejectReason reason)?
  onRangeStartRejected;

  /// Called when the user taps (a plain tap, not a long press) a day of the
  /// cycle on screen that has not come yet, which can not be used. Outside the
  /// cycle a tap does nothing and is not reported.
  final ValueChanged<DateTime>? onFutureDayTap;

  /// Called when the repository failed to load the confirmed days, with what
  /// it threw. Only with a [repository]; with `onVisibleRangeChanged` the
  /// screen does the loading and knows by itself. `controller.reload()` tries
  /// again.
  final ValueChanged<Object>? onLoadFailed;

  /// Called when the repository failed to confirm the days, with what it
  /// threw. The range is kept so the user can try again. Only with a
  /// [repository].
  final ValueChanged<Object>? onConfirmFailed;

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

  /// Places every part of the picker. When `null` the default layout is used:
  /// header, weekdays, grid, the "› Hướng dẫn" row (legend and "Cài đặt lịch")
  /// and, with a repository, the "Hủy" / "Xác nhận PCCT" buttons.
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

  /// The confirmed days that came from the repository, with their status.
  /// Keys are calendar days (`DateTime(y, m, d)`).
  final Map<DateTime, WorkStatus> _statuses = {};

  /// The repository is loading, or a confirmation is on its way.
  bool _loading = false;
  bool _confirming = false;

  /// Every load gets a number; an answer that is no longer the newest is
  /// dropped. `_dataVersion` changes when a confirmation was saved, so a load
  /// that started before it is asked again instead of overwriting it.
  int _loadGen = 0;
  int _dataVersion = 0;

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
    if (widget.repository != null) {
      _loading = true;
      _fetch();
    } else {
      _statuses.addAll(_statusMap(widget.confirmedDays));
      if (widget.onVisibleRangeChanged != null) {
        // The screen may start loading in this callback; wait for the first
        // frame so nothing is rebuilt in the middle of this one.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestVisibleRange();
        });
      }
    }
    if (widget.persistRestWeekdays) _restoreRestWeekdays();
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
    if (oldWidget.repository != widget.repository) {
      // Another source: ask it again (what is on screen stays until the
      // answer comes, so there is no flicker). Create the repository once and
      // keep it; a new instance on every build asks again on every build.
      _dataVersion++;
      if (widget.repository != null) {
        _loading = true;
        _fetch();
      } else {
        _statuses.clear();
        _loading = false;
      }
    }
    final keys = _keysOf(widget.confirmedDates);
    var changed =
        keys.length != _confirmedKeys.length ||
        !keys.containsAll(_confirmedKeys);
    _confirmedKeys = keys;
    if (widget.repository == null &&
        (widget.confirmedDays != null || oldWidget.confirmedDays != null)) {
      // The screen passed new data: draw it. Only a different set of days
      // (not a different status) invalidates the range.
      final next = _statusMap(widget.confirmedDays);
      if (next.length != _statuses.length ||
          !next.keys.every(_statuses.containsKey)) {
        changed = true;
      }
      _statuses
        ..clear()
        ..addAll(next);
    }
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

  bool _isConfirmed(DateTime d) =>
      _confirmedKeys.contains(_keyOf(d)) || _statuses.containsKey(_dateOnly(d));

  // ----------------------------------------------------------------- data

  /// The data comes from the screen, not from a repository.
  bool get _fromScreen => widget.repository == null;

  /// Loading, from the repository or from the screen.
  bool get _isLoading => _fromScreen ? widget.isLoading : _loading;

  /// Confirming, with the repository or on the screen's side.
  bool get _isConfirming => _fromScreen ? widget.isConfirming : _confirming;

  Map<DateTime, WorkStatus> _statusMap(List<ConfirmedDay>? days) => {
    for (final day in days ?? const <ConfirmedDay>[]) day.date: day.status,
  };

  /// Tells the screen which dates to load: the cycle plus 6 days on each side.
  void _requestVisibleRange() {
    widget.onVisibleRangeChanged?.call(
      _addDays(_cycle.start, -6),
      _addDays(_cycle.end, 6),
    );
  }

  Future<void> _reload() {
    if (widget.repository != null) return _fetch();
    _requestVisibleRange();
    return Future.value();
  }

  /// Loads the confirmed days of the cycle on screen from the repository: the
  /// cycle plus 6 days on each side, because the grid shows whole weeks.
  Future<void> _fetch() async {
    final repo = widget.repository;
    if (repo == null) return;
    final from = _addDays(_cycle.start, -6);
    final to = _addDays(_cycle.end, 6);
    final gen = ++_loadGen;
    final version = _dataVersion;
    if (!_loading && mounted) setState(() => _loading = true);
    List<ConfirmedDay> loaded;
    try {
      loaded = await repo.loadConfirmed(from, to);
    } catch (error) {
      if (!mounted || gen != _loadGen) return;
      setState(() => _loading = false);
      widget.onLoadFailed?.call(error);
      return;
    }
    if (!mounted || gen != _loadGen) return; // a newer load took over
    if (version != _dataVersion) return _fetch(); // confirmed meanwhile
    final next = {..._statuses}
      ..removeWhere((d, _) => !d.isBefore(from) && !d.isAfter(to));
    for (final day in loaded) {
      next[day.date] = day.status;
    }
    _applyStatuses(next);
  }

  /// Replaces the repository data. A range was built on the old data, so it is
  /// cancelled when the set of confirmed days changed (or when [forceCancel]).
  void _applyStatuses(
    Map<DateTime, WorkStatus> next, {
    bool forceCancel = false,
  }) {
    final changed =
        next.length != _statuses.length ||
        !next.keys.every(_statuses.containsKey);
    final hadRange = _anchor != null;
    final cancel = hadRange && (changed || forceCancel);
    setState(() {
      _statuses
        ..clear()
        ..addAll(next);
      _loading = false;
      if (cancel) _clearRange();
    });
    if (cancel) widget.onRangeCancelled?.call();
  }

  bool get _canConfirm {
    if (widget.repository == null && widget.onConfirm == null) return false;
    if (_isConfirming) return false;
    final selection = _selection();
    return selection != null && selection.validDays.isNotEmpty;
  }

  /// Sends the valid days to the repository (or to `onConfirm`). `true` when
  /// they were saved (handed over, with `onConfirm`).
  Future<bool> _confirm() async {
    final repo = widget.repository;
    if (!_canConfirm) return false;
    final selection = _selection()!;
    if (repo == null) {
      widget.onConfirm!(selection.validDays);
      return true;
    }
    setState(() => _confirming = true);
    List<ConfirmedDay> saved;
    try {
      saved = await repo.confirm(selection.validDays);
    } catch (error) {
      if (!mounted) return false;
      setState(() => _confirming = false);
      widget.onConfirmFailed?.call(error);
      return false;
    }
    if (!mounted) return false;
    _dataVersion++;
    final next = {..._statuses};
    for (final day in saved) {
      next[day.date] = day.status;
    }
    setState(() => _confirming = false);
    _applyStatuses(next, forceCancel: true);
    widget.onConfirmed?.call(saved);
    return true;
  }

  // -------------------------------------------------------- rest weekdays

  /// Puts back the rest days the user chose last time.
  Future<void> _restoreRestWeekdays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(widget.restWeekdaysKey);
      if (stored == null || !mounted) return;
      final restored = {
        for (final s in stored)
          if (int.tryParse(s) case final w? when w >= 1 && w <= 7) w,
      };
      if (setEquals(restored, _restWeekdays)) return;
      final hadRange = _anchor != null;
      setState(() {
        _restWeekdays = restored;
        if (hadRange) _clearRange();
      });
      if (hadRange) widget.onRangeCancelled?.call();
    } catch (_) {
      // No storage on this platform (or in a test): keep the default.
    }
  }

  Future<void> _saveRestWeekdays() async {
    if (!widget.persistRestWeekdays) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(widget.restWeekdaysKey, [
        for (final w in _restWeekdays) '$w',
      ]);
    } catch (_) {
      // Nothing to store into: the choice just is not remembered.
    }
  }

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
      status: _statuses[_dateOnly(date)],
    );
  }

  // -------------------------------------------------------------- actions

  void _goToCycle(DatePickerCycle cycle) {
    final hadRange = _anchor != null;
    setState(() {
      _clearRange();
      _cycle = cycle;
      _viewed = null;
      if (widget.repository != null) _loading = true;
    });
    if (widget.repository != null) {
      _fetch();
    } else {
      _requestVisibleRange();
    }
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

  void _onTap(DateTime date, {bool reportFutureDay = true}) {
    final info = _infoFor(date);
    if (!info.isTappable) {
      // A plain tap on a day of the cycle that has not come yet: tell the app.
      if (reportFutureDay && info.inCycle && info.isFuture) {
        widget.onFutureDayTap?.call(date);
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
      // Works like a tap, except that it does not report a day that has not
      // come: that is for a plain tap only.
      _onTap(date, reportFutureDay: false);
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
    _saveRestWeekdays();
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

  Widget _defaultDayCell(BuildContext context, RangeDayCellInfo info) =>
      RangePickerDayCell(info: info, theme: widget.theme);

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

  // ----------------------------------------------------- controller notices

  /// What the controller's listeners can see, as one number.
  int? _noticeKey;

  /// Tells the controller's listeners after this frame when something they can
  /// read has changed. Doing it from `build` covers every way the range or the
  /// flags can change, and waiting for the end of the frame keeps a listener
  /// from rebuilding in the middle of one.
  void _scheduleControllerNotice() {
    final controller = widget.controller;
    if (controller == null) return;
    final selection = _selection();
    final key = Object.hash(
      _anchor != null,
      _canConfirm,
      _isLoading,
      _isConfirming,
      selection?.start,
      selection?.end,
      Object.hashAll(selection?.validDays ?? const <DateTime>[]),
    );
    if (key == _noticeKey) return;
    final first = _noticeKey == null;
    _noticeKey = key;
    if (first) return; // nobody has seen an earlier value
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller == controller) controller._tell();
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _effectiveStart = _computeEffectiveStart();
    _effectiveEnd = _computeEffectiveEnd();
    _scheduleControllerNotice();
    final parts = CreateRangeDatePickerParts(
      selection: _selection(),
      viewedDate: _viewed,
      cancelRange: _cancelRange,
      restWeekdays: Set.unmodifiable(_restWeekdays),
      setRestWeekday: _setRestWeekday,
      isLoading: _isLoading,
      isConfirming: _isConfirming,
      canConfirm: _canConfirm,
      confirm: _confirm,
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
            : _defaultLayout(parts);

    return SizedBox(width: widget.width, child: body);
  }

  /// The layout used when no `builder` is given.
  Widget _defaultLayout(CreateRangeDatePickerParts parts) {
    final showActions = widget.showActionBar ?? widget.repository != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            parts.leftArrow,
            Expanded(child: Center(child: parts.title)),
            parts.rightArrow,
          ],
        ),
        parts.weekdayRow,
        parts.grid,
        // A thin line while the repository loads (the space is kept so the
        // layout does not jump).
        SizedBox(
          height: 2,
          child:
              parts.isLoading
                  ? LinearProgressIndicator(
                    key: const ValueKey('rdp-loading'),
                    color: widget.theme.ringColor,
                    backgroundColor: Colors.transparent,
                  )
                  : null,
        ),
        RangePickerGuideSection(
          restWeekdays: parts.restWeekdays,
          setRestWeekday: parts.setRestWeekday,
          theme: widget.theme,
          labels: widget.labels,
        ),
        if (showActions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: RangePickerActionBar(
              onCancel: parts.selection != null ? parts.cancelRange : null,
              onConfirm: parts.canConfirm ? () => parts.confirm() : null,
              isConfirming: parts.isConfirming,
              theme: widget.theme,
              labels: widget.labels,
            ),
          ),
      ],
    );
  }
}
