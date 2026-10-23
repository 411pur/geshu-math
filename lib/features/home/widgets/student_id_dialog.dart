import 'package:flutter/material.dart';

Future<void> showStudentIdDialog(
  BuildContext context, {
  required ValueChanged<String> onSave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StudentIdDialog(onSave: onSave),
  );
}

class _StudentIdDialog extends StatefulWidget {
  const _StudentIdDialog({required this.onSave});

  final ValueChanged<String> onSave;

  @override
  State<_StudentIdDialog> createState() => _StudentIdDialogState();
}

class _StudentIdDialogState extends State<_StudentIdDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    widget.onSave(id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入学号'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(hintText: '学号'),
        autofocus: true,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        FilledButton(
          onPressed: _save,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
