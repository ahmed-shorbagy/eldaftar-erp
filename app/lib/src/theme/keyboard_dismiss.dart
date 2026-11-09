import 'package:flutter/widgets.dart';

/// Closes the on-screen keyboard. Used by multi-line fields and forms.
void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// For TextField.onTapOutside.
void dismissKeyboardOnTapOutside(PointerDownEvent _) => dismissKeyboard();
