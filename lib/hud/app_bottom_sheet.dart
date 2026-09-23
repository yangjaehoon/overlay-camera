import 'package:flutter/material.dart';

/// 앱 전역에서 쓰는 바텀시트 배경색.
const appBottomSheetColor = Color(0xFF1C1C1E);

/// 앱 전역에서 쓰는 바텀시트 모서리 모양(위쪽만 둥글게).
const appBottomSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
);

/// 바텀시트 제목 텍스트 스타일.
const sheetTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

/// 바텀시트 맨 위의 드래그 핸들(끌어내려 닫을 수 있다는 힌트).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 앱 공통 스타일(어두운 배경 + 위쪽 둥근 모서리)의 바텀시트를 띄운다.
/// [scrollable]이면 내용이 길 때를 대비해 화면의 최대 85%까지 늘어나고
/// 그 안에서 스크롤되게 한다(작은 폰에서 내용이 잘리지 않도록).
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollable,
    backgroundColor: appBottomSheetColor,
    constraints: scrollable
        ? BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85)
        : null,
    shape: appBottomSheetShape,
    builder: builder,
  );
}
