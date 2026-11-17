import 'package:create_date_picker/create_date_picker.dart';

/// Demo of `disabledWeekdays`: Sundays are faded and can not be selected.
///
/// 1. Default look.
/// 2. An existing custom `dateCellBuilder` (no changes needed in the builder).
/// 3. A dedicated `disabledDateCellBuilder` for the disabled weekdays.
class Example4 extends StatefulWidget {
  const Example4({super.key});

  @override
  State<Example4> createState() => _Example4State();
}

class _Example4State extends State<Example4> {
  DateTime? _lastSelected1;
  DateTime? _lastSelected2;
  DateTime? _lastSelected3;
  DateTime? _lastSelected4;

  String _format(DateTime? date) =>
      date == null
          ? 'Selected: -'
          : 'Selected: ${date.day}/${date.month}/${date.year} (weekday ${date.weekday})';

  // An "old style" builder: it knows nothing about disabledWeekdays.
  Widget _legacyDateCellBuilder(
    selectdate,
    isSelected,
    isInTheCurrentMonth,
    isAvailable,
    day,
    isToday,
  ) => GestureDetector(
    onTap: selectdate,
    child: Card(
      color: isSelected ? Colors.orange : Colors.grey.withValues(alpha: 0.1),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            color:
                isInTheCurrentMonth
                    ? (isSelected ? Colors.white : Colors.black)
                    : Colors.grey,
          ),
        ),
      ),
    ),
  );

  Widget _disabledDateCellBuilder(
    DateTime date,
    bool isInTheCurrentMonth,
    bool isToday,
  ) => Center(
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          color: Colors.grey,
          decoration: TextDecoration.lineThrough,
          fontSize: isInTheCurrentMonth ? 14 : 11,
        ),
      ),
    ),
  );

  Widget _section(String title, Widget picker, DateTime? selected) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: const TextStyle(fontSize: 16)),
      picker,
      Text(_format(selected)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            '1. Default + disabledWeekdays',
            CreateDatePicker(
              width: 340,
              disabledWeekdays: const {DateTime.sunday},
              onSelectedDateChanged:
                  (date) => setState(() => _lastSelected1 = date),
            ),
            _lastSelected1,
          ),
          _section(
            '2. Legacy dateCellBuilder (auto faded)',
            CreateDatePicker(
              width: 340,
              disabledWeekdays: const {DateTime.sunday},
              dateCellBuilder: _legacyDateCellBuilder,
              onSelectedDateChanged:
                  (date) => setState(() => _lastSelected2 = date),
            ),
            _lastSelected2,
          ),
          _section(
            '3. disabledDateCellBuilder',
            CreateDatePicker(
              width: 340,
              disabledWeekdays: const {DateTime.sunday},
              dateCellBuilder: _legacyDateCellBuilder,
              disabledDateCellBuilder: _disabledDateCellBuilder,
              onSelectedDateChanged:
                  (date) => setState(() => _lastSelected3 = date),
            ),
            _lastSelected3,
          ),
          _section(
            '4. Today is a disabled weekday',
            CreateDatePicker(
              width: 340,
              // Disables whatever weekday today is, to show the "today can
              // not be selected" case on any day of the week.
              disabledWeekdays: {DateTime.now().weekday},
              onSelectedDateChanged:
                  (date) => setState(() => _lastSelected4 = date),
            ),
            _lastSelected4,
          ),
        ],
      ),
    );
  }
}
