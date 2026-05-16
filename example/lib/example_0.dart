import 'package:create_date_picker/create_date_picker.dart';

class Example0 extends StatelessWidget {
  const Example0({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Default', style: TextStyle(fontSize: 16)),
        CreateDatePicker(
          width: 450,
          popupMenuOffset: Offset(20, 5),
          markedDates: [
            DateTime.now().add(Duration(days: 2)),
            DateTime.now().add(Duration(days: 4)),
            DateTime.now().add(Duration(days: 6)),
          ],
          onSwipeLeftSelectedDate: (date) {},
          onSwipeRightSelectedDate: (date) {},
          onSelectedDateChanged: (date) {},
        ),
      ],
    );
  }
}
