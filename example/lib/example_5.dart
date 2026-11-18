import 'package:create_date_picker/create_date_picker.dart';

/// Demo of `CreateRangeDatePicker`: a timesheet calendar that shows one cycle
/// (26 of last month → 25 of this month).
///
/// * Tap a day to look at it (ring + "Viewing" below).
/// * Long-press (0.5 s) the earliest day that is not confirmed to start a
///   range, then tap a working day to set the end.
/// * Rest days inside the range are skipped; tap one to make it count.
/// * "Hủy" cancels the range, "Xác nhận PCCT" confirms the valid days.
/// * "› Hướng dẫn" opens the legend; the gear next to it closes the legend and
///   opens "Cài đặt lịch", where the user chooses the rest days.
///
/// The dots (Onsite / Offsite) are made up: the package only tells the app
/// which day is which, the app draws whatever it wants.
/// Which part of the "Hướng dẫn" row is open.
enum _Panel { none, guide, settings }

class Example5 extends StatefulWidget {
  const Example5({super.key});

  @override
  State<Example5> createState() => _Example5State();
}

class _Example5State extends State<Example5> {
  static const _green = Color(0xFF0F6B5C);
  static const _onsite = Color(0xFFC45C16);
  static const _offsite = Color(0xFF1F5F99);
  static const _lockedFill = Color(0xFFFFDCCB); // light orange
  static const _skipFill = Color(0xFFEDEDED);
  static const _lockedText = Color(0xFFD9772B);

  final _controller = CreateRangeDatePickerController();
  late Set<DateTime> _confirmed;
  DateTime? _viewed;
  Set<int> _rest = {DateTime.sunday};
  CreateRangeSelection? _selection;
  _Panel _panel = _Panel.none;

  @override
  void initState() {
    super.initState();
    final cycle = DatePickerCycle.containing(DateTime.now());
    // Pretend the first week of the cycle is already confirmed ...
    _confirmed = {
      for (var i = 0; i < 8; i++)
        DateTime(cycle.start.year, cycle.start.month, cycle.start.day + i),
    };
    // ... and also the first Sunday after it (confirmed on its own). A range
    // that runs over this Sunday shows the orange "Đã chấm" bar on it.
    var sunday = DateTime(
      cycle.start.year,
      cycle.start.month,
      cycle.start.day + 8,
    );
    while (sunday.weekday != DateTime.sunday) {
      sunday = DateTime(sunday.year, sunday.month, sunday.day + 1);
    }
    _confirmed.add(sunday);
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}';

  /// Only a confirmed day has a status dot. The status itself is made up here;
  /// a real app would read it from its own data.
  Color? _dotOf(RangeDayCellInfo info) {
    if (!info.isConfirmed) return null;
    return info.date.day % 3 == 0 ? _offsite : _onsite;
  }

  void _syncSelection() => setState(() => _selection = _controller.selection);

  Widget _cell(BuildContext context, RangeDayCellInfo info) {
    // Out of the cycle and in the future: faded. A day of the next cycle that
    // has already come (e.g. 26/11 while looking at the old cycle) can be
    // tapped to look at it, so it is not faded.
    final faded = !info.isTappable;
    var textColor = Colors.black87;
    Color? fill;
    if (info.isRestDay) textColor = Colors.black45;
    if (info.isRangeStart) {
      fill = const Color(0xFF1B5E20);
      textColor = Colors.white;
    } else if (info.isRangeEnd) {
      fill = const Color(0xFF2E7D32);
      textColor = Colors.white;
    } else if (info.isLocked) {
      // "Đã chấm" inside the range: striped, light orange, number struck out.
      fill = _lockedFill;
      textColor = _lockedText;
    } else if (info.isInRange && !info.isSkipped) {
      fill = const Color(0xFFDDF1E0);
    }
    if (info.isSkipped) {
      // A rest day that does not count: the same stripes, in grey.
      fill = const Color(0xFFEDEDED);
      textColor = Colors.black38;
    }

    final dot = _dotOf(info);
    return Center(
      child: Opacity(
        opacity: faded ? 0.35 : 1,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border: info.isViewed ? Border.all(color: _green, width: 1) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (info.isSkipped || info.isLocked)
                  const Positioned.fill(
                    child: CustomPaint(painter: _HatchPainter()),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${info.date.day}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight:
                            info.isToday ? FontWeight.w800 : FontWeight.w400,
                        decoration:
                            info.isLocked ? TextDecoration.lineThrough : null,
                        decorationColor: _lockedText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 6,
                      child:
                          dot == null
                              ? null
                              : Container(
                                width: 6,
                                decoration: BoxDecoration(
                                  color: dot,
                                  shape: BoxShape.circle,
                                ),
                              ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendItem(Widget mark, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      mark,
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 10),
    ],
  );

  Widget _dotMark(Color c) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget _builder(BuildContext context, CreateRangeDatePickerParts parts) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        _guideSection(parts),
      ],
    );
  }

  /// The legend: what the dots and the cell styles mean.
  Widget _legend() {
    return Wrap(
      runSpacing: 6,
      children: [
        _legendItem(_dotMark(_onsite), 'Onsite'),
        _legendItem(_dotMark(_offsite), 'Offsite'),
        _legendItem(
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _lockedFill,
              borderRadius: BorderRadius.circular(3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: const CustomPaint(painter: _HatchPainter()),
            ),
          ),
          'Đã chấm',
        ),
        _legendItem(
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _skipFill,
              borderRadius: BorderRadius.circular(3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: const CustomPaint(painter: _HatchPainter()),
            ),
          ),
          'Bỏ qua',
        ),
      ],
    );
  }

  static const _guideColor = Color(0xFF5B6770);

  void _togglePanel(_Panel panel) =>
      setState(() => _panel = _panel == panel ? _Panel.none : panel);

  /// The "› Hướng dẫn" row. Tapping the title opens or closes the legend,
  /// tapping the gear closes the legend and opens "Cài đặt lịch" (and the
  /// other way round). Only one of the two is open at a time.
  Widget _guideSection(CreateRangeDatePickerParts parts) {
    final guideOpen = _panel == _Panel.guide;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFE4E4E4)),
        Row(
          children: [
            InkWell(
              onTap: () => _togglePanel(_Panel.guide),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedRotation(
                      turns: guideOpen ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: _guideColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      'Hướng dẫn',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _guideColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Cài đặt lịch',
              onPressed: () => _togglePanel(_Panel.settings),
              icon: const Icon(Icons.settings_outlined),
              iconSize: 18,
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: switch (_panel) {
            _Panel.none => const SizedBox(width: double.infinity),
            _Panel.guide => Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: _legend(),
            ),
            _Panel.settings => _settingsCard(parts),
          },
        ),
      ],
    );
  }

  /// "Cài đặt lịch": the user decides which weekdays are rest days. The
  /// package only keeps the answer; it is saved by the app (here: `_rest`).
  Widget _settingsCard(CreateRangeDatePickerParts parts) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6DCE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cài đặt lịch',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _restRow(parts, DateTime.saturday, 'Thứ 7 là ngày nghỉ'),
          _restRow(parts, DateTime.sunday, 'Chủ nhật là ngày nghỉ'),
        ],
      ),
    );
  }

  Widget _restRow(CreateRangeDatePickerParts parts, int weekday, String label) {
    final checked = parts.restWeekdays.contains(weekday);
    return InkWell(
      onTap: () => parts.setRestWeekday(weekday, !checked),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: checked ? _green : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: checked ? _green : const Color(0xFFB8C0CC),
                  width: 1.5,
                ),
              ),
              child:
                  checked
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
            ),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: CreateRangeDatePicker(
                width: 380,
                controller: _controller,
                confirmedDates: _confirmed,
                initialRestWeekdays: _rest,
                builder: _builder,
                dayCellBuilder: _cell,
                onRestWeekdaysChanged: (rest) => setState(() => _rest = rest),
                onDateTap: (date) => setState(() => _viewed = date),
                onCycleChanged: (_, _) => setState(() => _viewed = null),
                onRangeChanged: (_, _, _) => _syncSelection(),
                onRangeCancelled: _syncSelection,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Viewing: ${_viewed == null ? '-' : '${_fmt(_viewed!)}/${_viewed!.year}'}',
                  ),
                  Text(
                    selection == null
                        ? 'Range: -'
                        : 'Range: ${_fmt(selection.start)} → '
                            '${selection.end == null ? '?' : _fmt(selection.end!)}',
                  ),
                  Text(
                    'Valid days: ${selection == null || selection.validDays.isEmpty ? '-' : selection.validDays.map(_fmt).join(', ')}',
                  ),
                  Text('Rest weekdays: ${(_rest.toList()..sort())}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed:
                            selection == null ? null : _controller.cancelRange,
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed:
                            selection == null || selection.validDays.isEmpty
                                ? null
                                : () {
                                  final days = selection.validDays;
                                  setState(
                                    () => _confirmed = {..._confirmed, ...days},
                                  );
                                },
                        child: const Text('Xác nhận PCCT'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wide light diagonal stripes drawn over the fill of a cell.
class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.65)
          ..strokeWidth = 3;
    for (double x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => false;
}
