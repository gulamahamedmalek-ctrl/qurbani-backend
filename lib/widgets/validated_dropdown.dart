import 'package:flutter/material.dart';

class ValidatedDropdownMenu extends StatefulWidget {
  final String label;
  final List<String> options;
  final String? initialSelection;
  final ValueChanged<String?> onSelected;
  final double? width;
  final double? menuHeight;
  final EdgeInsetsGeometry? expandedInsets;
  final InputDecorationTheme? inputDecorationTheme;
  final bool showLabelAbove;

  const ValidatedDropdownMenu({
    super.key,
    required this.label,
    required this.options,
    this.initialSelection,
    required this.onSelected,
    this.width,
    this.menuHeight = 200,
    this.expandedInsets,
    this.inputDecorationTheme,
    this.showLabelAbove = true,
  });

  @override
  State<ValidatedDropdownMenu> createState() => _ValidatedDropdownMenuState();
}

class _ValidatedDropdownMenuState extends State<ValidatedDropdownMenu> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSelection ?? '');
    _controller.addListener(_validate);
  }

  @override
  void didUpdateWidget(covariant ValidatedDropdownMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSelection != widget.initialSelection && widget.initialSelection != null) {
      if (_controller.text != widget.initialSelection) {
        _controller.text = widget.initialSelection!;
      }
    }
  }

  void _validate() {
    final text = _controller.text;
    if (text.isNotEmpty && !widget.options.contains(text)) {
      if (_errorText == null) {
        setState(() => _errorText = 'Invalid selection');
      }
    } else {
      if (_errorText != null) {
        setState(() => _errorText = null);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownMenu<String>(
      controller: _controller,
      initialSelection: widget.initialSelection,
      width: widget.width,
      expandedInsets: widget.expandedInsets,
      menuHeight: widget.menuHeight,
      errorText: _errorText,
      enableFilter: true, // Allow filtering while typing
      textStyle: const TextStyle(fontSize: 13),
      inputDecorationTheme: widget.inputDecorationTheme ?? InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
      dropdownMenuEntries: widget.options.map((opt) => DropdownMenuEntry(value: opt, label: opt)).toList(),
      onSelected: (val) {
        _validate();
        widget.onSelected(val);
      },
    );

    if (!widget.showLabelAbove) return dropdown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(widget.label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        ),
        dropdown,
      ],
    );
  }
}
