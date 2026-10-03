part of '../../app.dart';

String modLabel(ModStatus x) => switch (x.kind) {
  ModStateKind.applied => '已安装：${x.version ?? '未知版本'}',
  ModStateKind.notApplied => '未安装',
};

class SetRow extends StatelessWidget {
  const SetRow(this.label, this.value, {super.key});
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          SizedBox(
            width: constraints.maxWidth < 450 ? 90 : 150,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: value),
        ],
      ),
    ),
  );
}

Future<bool> dialog(BuildContext c, String t, String b) async =>
    (await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(t),
        content: Text(b),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('继续'),
          ),
        ],
      ),
    )) ??
    false;
