import 'package:create_date_picker/create_date_picker.dart';

class Example5 extends StatefulWidget {
  const Example5({super.key});

  @override
  State<Example5> createState() => _Example5State();
}

class _Example5State extends State<Example5> {
  final _api = _FakeApi();
  final _controller = CreateRangeDatePickerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  WorkStatus _status = WorkStatus.onsite; // chosen in the app
  List<ConfirmedDay> _attendances = const [];

  (DateTime, DateTime)? _window;
  bool _dialogOpen = false;

  void _showLoading() {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const PopScope(
            canPop: false,
            child: Center(child: CircularProgressIndicator()),
          ),
    );
  }

  void _hideLoading() {
    if (!_dialogOpen || !mounted) return;
    _dialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _say(String text, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 5),
          action:
              retry == null
                  ? null
                  : SnackBarAction(label: 'Thử lại', onPressed: retry),
        ),
      );
  }

  Future<void> _reload(DateTime from, DateTime to) async {
    _window = (from, to);
    _showLoading();
    await _loadWindow();
    _hideLoading();
  }

  Future<void> _loadWindow() async {
    final window = _window;
    if (window == null) return;
    try {
      final days = await _api.fetch(window.$1, window.$2);
      if (mounted) setState(() => _attendances = days);
    } catch (_) {
      _say(
        'Không tải được dữ liệu - Vui lòng thử lại',
        retry: _controller.reload,
      );
    }
  }

  Future<void> _confirm(List<DateTime> days) async {
    _showLoading();
    try {
      await _api.save(days, _status);
    } catch (_) {
      _hideLoading();
      _say('Xác nhận không thành công - Vui lòng thử lại');
      return;
    }
    await _loadWindow();
    _hideLoading();
  }

  void _onRejected(DateTime date, RangeStartRejectReason reason) {
    switch (reason) {
      case RangeStartRejectReason.confirmed:
        _say(
          'Ngày đã xác nhận - Vui lòng chọn ngày chưa xác nhận xa nhất để bắt đầu',
        );
      case RangeStartRejectReason.outsideCycle:
        _say('Ngày ngoài kỳ - Không thể xác nhận');
      case RangeStartRejectReason.notEarliest:
        _say(
          'Các ngày phải xác nhận liên tiếp, không được xen kẽ - Vui lòng chọn lại ngày',
        );
      case RangeStartRejectReason.future:
        break; // a long press on a day that has not come: say nothing
    }
  }

  void _onFutureDayTap(DateTime date) =>
      _say('Ngày này chưa thể xác nhận - Vui lòng chọn ngày khác');

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 40),
        child: SizedBox(
          width: 404,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final s in WorkStatus.values)
                    ChoiceChip(
                      label: Text(
                        s == WorkStatus.onsite ? 'Onsite' : 'Offsite',
                      ),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: CreateRangeDatePicker(
                  width: double.infinity,
                  controller: _controller,
                  confirmedDays: _attendances,
                  onVisibleRangeChanged: _reload,
                  onConfirm: _confirm,
                  onRangeStartRejected: _onRejected,
                  onFutureDayTap: _onFutureDayTap,
                ),
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _controller,
                builder:
                    (context, _) => Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                _controller.hasRange
                                    ? _controller.cancelRange
                                    : null,
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                _controller.canConfirm
                                    ? _controller.confirm
                                    : null,
                            child: const Text('Xác nhận PCCT'),
                          ),
                        ),
                      ],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FakeApi {
  _FakeApi() {
    DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
    WorkStatus pick(DateTime d) =>
        d.day % 3 == 0 ? WorkStatus.offsite : WorkStatus.onsite;

    final current = DatePickerCycle.containing(DateTime.now());
    var sunday = add(current.start, 8);
    while (sunday.weekday != DateTime.sunday) {
      sunday = add(sunday, 1);
    }
    for (
      var d = add(current.start, -200);
      d.isBefore(current.start);
      d = add(d, 1)
    ) {
      _days[d] = pick(d);
    }
    for (var i = 0; i < 8; i++) {
      final d = add(current.start, i);
      _days[d] = pick(d);
    }
    _days[sunday] = WorkStatus.onsite;
  }

  final Map<DateTime, WorkStatus> _days = {};

  static const _latency = Duration(milliseconds: 600);

  Future<List<ConfirmedDay>> fetch(DateTime from, DateTime to) async {
    await Future<void>.delayed(_latency);
    return [
      for (final e in _days.entries)
        if (!e.key.isBefore(from) && !e.key.isAfter(to))
          ConfirmedDay(e.key, e.value),
    ];
  }

  Future<void> save(List<DateTime> days, WorkStatus status) async {
    await Future<void>.delayed(_latency);
    for (final d in days) {
      _days[DateTime(d.year, d.month, d.day)] = status;
    }
  }
}
