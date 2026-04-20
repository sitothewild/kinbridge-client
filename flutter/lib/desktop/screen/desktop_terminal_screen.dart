import 'package:flutter/material.dart';
import 'package:kinbridge_support/common.dart';
import 'package:provider/provider.dart';

import 'package:kinbridge_support/desktop/pages/terminal_tab_page.dart';

class DesktopTerminalScreen extends StatelessWidget {
  final Map<String, dynamic> params;

  const DesktopTerminalScreen({Key? key, required this.params})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.ffiModel),
      ],
      child: Scaffold(
        backgroundColor: isLinux ? Colors.transparent : null,
        body: TerminalTabPage(
          params: params,
        ),
      ),
    );
  }
}
