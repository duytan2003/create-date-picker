import 'package:flutter/material.dart';

import 'create_range_date_picker.dart';
import 'range_picker_models.dart';

/// The default look of one day of [CreateRangeDatePicker]. Used when
/// `dayCellBuilder` is not given; an app that draws its own cells can still
/// call it for the days it does not want to change.
class RangePickerDayCell extends StatelessWidget {
  /// Draws [info] with the colours of [theme].
  const RangePickerDayCell({
    super.key,
    required this.info,
    this.theme = const RangePickerTheme(),
  });

  /// What the picker knows about the day.
  final RangeDayCellInfo info;

  /// The colours.
  final RangePickerTheme theme;

  Color? _dotColor() => switch (info.status) {
    WorkStatus.onsite => theme.onsiteColor,
    WorkStatus.offsite => theme.offsiteColor,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    // Out of the cycle and in the future: faded. A day of the next cycle that
    // has already come can be tapped, so it is not faded.
    final faded = !info.isTappable;
    var textColor = theme.dayText;
    Color? fill;
    if (info.isRestDay) textColor = theme.restDayText;
    if (info.isRangeStart) {
      fill = theme.rangeStartFill;
      textColor = theme.onRangeEnds;
    } else if (info.isRangeEnd) {
      fill = theme.rangeEndFill;
      textColor = theme.onRangeEnds;
    } else if (info.isLocked) {
      // A confirmed day inside the range: striped, light orange, struck out.
      fill = theme.confirmedFill;
      textColor = theme.confirmedText;
    } else if (info.isInRange && !info.isSkipped) {
      fill = theme.rangeFill;
    }
    if (info.isSkipped) {
      // A rest day that does not count: the same stripes, in grey.
      fill = theme.skippedFill;
      textColor = theme.skippedText;
    }

    final dot = _dotColor();
    return Center(
      child: Opacity(
        opacity: faded ? 0.35 : 1,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border:
                info.isViewed
                    ? Border.all(color: theme.ringColor, width: 1)
                    : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (info.isSkipped || info.isLocked)
                  const Positioned.fill(
                    child: CustomPaint(painter: RangePickerHatchPainter()),
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
                        decorationColor: theme.confirmedText,
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
}

/// Wide light diagonal stripes drawn over the fill of a cell.
class RangePickerHatchPainter extends CustomPainter {
  /// Const painter, there is nothing to configure.
  const RangePickerHatchPainter();

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
  bool shouldRepaint(RangePickerHatchPainter old) => false;
}

enum _Panel { none, guide, settings }

/// The "› Hướng dẫn" row of the default layout. Tapping the title opens or
/// closes the legend; tapping the gear closes the legend and opens "Cài đặt
/// lịch" (two checkboxes for the rest days), and the other way round. Only one
/// of the two is open at a time.
class RangePickerGuideSection extends StatefulWidget {
  /// Needs the rest days and the function that changes them (both are in
  /// `CreateRangeDatePickerParts`).
  const RangePickerGuideSection({
    super.key,
    required this.restWeekdays,
    required this.setRestWeekday,
    this.theme = const RangePickerTheme(),
    this.labels = const RangePickerLabels(),
  });

  /// The weekdays that are rest days now.
  final Set<int> restWeekdays;

  /// Marks a weekday as a rest day or not.
  final void Function(int weekday, bool isRestDay) setRestWeekday;

  /// The colours.
  final RangePickerTheme theme;

  /// The texts.
  final RangePickerLabels labels;

  @override
  State<RangePickerGuideSection> createState() =>
      _RangePickerGuideSectionState();
}

class _RangePickerGuideSectionState extends State<RangePickerGuideSection> {
  _Panel _panel = _Panel.none;

  RangePickerTheme get _t => widget.theme;
  RangePickerLabels get _l => widget.labels;

  void _toggle(_Panel panel) =>
      setState(() => _panel = _panel == panel ? _Panel.none : panel);

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

  Widget _stripeMark(Color fill) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(3),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: const CustomPaint(painter: RangePickerHatchPainter()),
    ),
  );

  Widget _legend() => Wrap(
    runSpacing: 6,
    children: [
      _legendItem(_dotMark(_t.onsiteColor), _l.onsite),
      _legendItem(_dotMark(_t.offsiteColor), _l.offsite),
      _legendItem(_stripeMark(_t.confirmedFill), _l.confirmedLegend),
      _legendItem(_stripeMark(_t.skippedFill), _l.skippedLegend),
    ],
  );

  Widget _restRow(int weekday, String label) {
    final checked = widget.restWeekdays.contains(weekday);
    return InkWell(
      onTap: () => widget.setRestWeekday(weekday, !checked),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: checked ? _t.ringColor : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: checked ? _t.ringColor : const Color(0xFFB8C0CC),
                  width: 1.5,
                ),
              ),
              child:
                  checked
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 16))),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    decoration: BoxDecoration(
      color: _t.cardFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _t.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l.settings,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _restRow(DateTime.saturday, _l.saturdayRest),
        _restRow(DateTime.sunday, _l.sundayRest),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final guideOpen = _panel == _Panel.guide;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 16, thickness: 1, color: _t.dividerColor),
        Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  key: const ValueKey('rdp-guide-toggle'),
                  onTap: () => _toggle(_Panel.guide),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedRotation(
                          turns: guideOpen ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.chevron_right,
                            size: 22,
                            color: _t.guideColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            _l.guide,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: _t.guideColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('rdp-guide-settings'),
              tooltip: _l.settings,
              onPressed: () => _toggle(_Panel.settings),
              icon: Icon(Icons.settings_outlined, color: _t.guideColor),
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
            _Panel.settings => _settingsCard(),
          },
        ),
      ],
    );
  }
}

/// The "Hủy" and "Xác nhận PCCT" buttons of the default layout.
class RangePickerActionBar extends StatelessWidget {
  /// Both buttons are disabled when their callback is `null`.
  const RangePickerActionBar({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.isConfirming = false,
    this.theme = const RangePickerTheme(),
    this.labels = const RangePickerLabels(),
  });

  /// Cancels the range; `null` disables the button (nothing to cancel).
  final VoidCallback? onCancel;

  /// Confirms the valid days; `null` disables the button.
  final VoidCallback? onConfirm;

  /// A confirmation is on its way: the button shows a spinner.
  final bool isConfirming;

  /// The colours.
  final RangePickerTheme theme;

  /// The texts.
  final RangePickerLabels labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton(
          key: const ValueKey('rdp-cancel'),
          onPressed: onCancel,
          child: Text(labels.cancelButton),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('rdp-confirm'),
          onPressed: onConfirm,
          style: FilledButton.styleFrom(backgroundColor: theme.ringColor),
          child:
              isConfirming
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : Text(labels.confirmButton),
        ),
      ],
    );
  }
}
