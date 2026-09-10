import 'package:flutter/material.dart';

/// 이름을 입력받는다. 취소하거나 빈 이름이면 null.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, hint: hint, initial: initial),
  );
  final trimmed = result?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// TextEditingController 수명을 위젯이 직접 관리한다
/// (다이얼로그 종료 애니메이션 중 컨트롤러를 dispose 하면 assert 로 죽는다).
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.hint, this.initial = ''});

  final String title;
  final String? hint;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
