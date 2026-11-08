import 'package:flutter/material.dart';

import '../domain/customer_rules.dart';
import '../domain/phone_countries.dart';

class CustomerPhoneField extends StatefulWidget {
  const CustomerPhoneField({
    super.key,
    required this.controller,
    required this.fieldKey,
    this.label = 'رقم الهاتف',
    this.enabled = true,
    this.allowEmpty = true,
    this.emptyMessage = 'أدخل رقم الهاتف.',
  });

  final TextEditingController controller;
  final Key fieldKey;
  final String label;
  final bool enabled;
  final bool allowEmpty;
  final String emptyMessage;

  @override
  CustomerPhoneFieldState createState() => CustomerPhoneFieldState();
}

class CustomerPhoneFieldState extends State<CustomerPhoneField> {
  late final TextEditingController _national;
  late PhoneCountry _country;
  String? _error;

  @override
  void initState() {
    super.initState();
    final split = splitCustomerPhone(widget.controller.text);
    _country = split.country;
    _national = TextEditingController(text: split.national);
  }

  @override
  void didUpdateWidget(CustomerPhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _applyStored(widget.controller.text);
    }
  }

  @override
  void dispose() {
    _national.dispose();
    super.dispose();
  }

  void _applyStored(String raw) {
    final split = splitCustomerPhone(raw);
    _country = split.country;
    _national.text = split.national;
  }

  /// Keeps [CustomerPhoneField.controller] current on every edit, so the
  /// number survives when the field is removed from the tree (a collapsed
  /// section or another form step). A valid number is stored as E.164; an
  /// incomplete one keeps its country code so review still rejects it.
  void _sync() {
    final raw = _national.text.trim();
    if (raw.isEmpty) {
      widget.controller.text = '';
      return;
    }
    final check = checkCustomerPhone(_country, raw);
    if (check is PhoneAccepted) {
      widget.controller.text = check.e164;
      return;
    }
    final digits = foldCustomerDigits(raw).replaceAll(RegExp(r'[\s-]'), '');
    widget.controller.text = digits.startsWith('+') || digits.startsWith('00')
        ? digits
        : '+${_country.dial}${digits.startsWith('0') ? digits.substring(1) : digits}';
  }

  /// Empty is accepted when [CustomerPhoneField.allowEmpty]. A valid number
  /// is written back to [CustomerPhoneField.controller] as E.164.
  bool validate() {
    final message = _message(_national.text);
    if (mounted) setState(() => _error = message);
    return message == null;
  }

  String? _message(String raw) {
    if (raw.trim().isEmpty) {
      if (!widget.allowEmpty) return widget.emptyMessage;
      widget.controller.text = '';
      return null;
    }
    final check = checkCustomerPhone(_country, raw);
    if (check is PhoneRejected) return check.message;
    if (check is PhoneAccepted) widget.controller.text = check.e164;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<PhoneCountry>(
              key: Key('${widget.fieldKey}-country'),
              value: _country,
              underline: const SizedBox.shrink(),
              items: [
                for (final country in phoneCountries)
                  DropdownMenuItem(
                    value: country,
                    child: Text('${country.nameAr} +${country.dial}'),
                  ),
              ],
              selectedItemBuilder: (context) => [
                for (final country in phoneCountries)
                  Text('+${country.dial}', textDirection: TextDirection.ltr),
              ],
              onChanged: widget.enabled
                  ? (value) {
                      if (value == null) return;
                      setState(() {
                        _country = value;
                        _error = null;
                      });
                      _sync();
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: widget.fieldKey,
                controller: _national,
                enabled: widget.enabled,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: widget.label,
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onChanged: (_) {
                  _sync();
                  if (_error != null) setState(() => _error = null);
                },
                validator: (value) {
                  final message = _message(value ?? '');
                  if (message != _error) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _error = message);
                    });
                  }
                  return message;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
