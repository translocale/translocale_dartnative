import 'dart:async';
import 'package:dartnative/dartnative.dart';
import 'controller.dart';

/// Access translations from descendants; changes rebuild dependent widgets.
class TransLocaleScope<T extends Object> extends InheritedWidget {
  TransLocaleScope({
    super.key,
    required this.translations,
    required super.child,
  }) : revision = translations.revision;
  final TransLocale<T> translations;
  final int revision;

  static TransLocale<T> of<T extends Object>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TransLocaleScope<T>>();
    if (scope == null) {
      throw StateError('Add TransLocaleBuilder above this widget.');
    }
    return scope.translations;
  }

  @override
  bool updateShouldNotify(TransLocaleScope<T> oldWidget) =>
      translations != oldWidget.translations || revision != oldWidget.revision;
}

/// Owns its controller, updates descendants, and pauses polling in the background.
/// Create the controller outside build. Do not share it between builders.
class TransLocaleBuilder<T extends Object> extends StatefulWidget {
  const TransLocaleBuilder({
    super.key,
    required this.translations,
    required this.builder,
    this.automaticUpdates = true,
  });
  final TransLocale<T> translations;
  final Widget Function(BuildContext context, T strings) builder;
  final bool automaticUpdates;

  @override
  State<TransLocaleBuilder<T>> createState() => _TransLocaleBuilderState<T>();
}

class _TransLocaleBuilderState<T extends Object>
    extends State<TransLocaleBuilder<T>>
    with WidgetsBindingObserver {
  void Function()? _unsubscribe;
  bool _ready = false, _started = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _started = false;
    widget.translations.setActive(false);
    _unsubscribe = widget.translations.addListener(() {
      if (mounted) setState(() {});
    });
    _schedule();
  }

  void _schedule() {
    _ready = false;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _ready = true;
      _activate(WidgetsBinding.instance.lifecycleState);
    });
  }

  void _activate(AppLifecycleState? state) {
    if (!_ready) return;
    final active =
        widget.automaticUpdates &&
        (state == null || state == AppLifecycleState.resumed);
    widget.translations.setActive(active);
    if (active && !_started) {
      _started = true;
      unawaited(widget.translations.start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _activate(state);

  @override
  void didUpdateWidget(covariant TransLocaleBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.translations != widget.translations) {
      _unsubscribe?.call();
      oldWidget.translations.dispose();
      _attach();
    } else if (oldWidget.automaticUpdates != widget.automaticUpdates) {
      if (!widget.automaticUpdates) widget.translations.setActive(false);
      _schedule();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe?.call();
    widget.translations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TransLocaleScope<T>(
    translations: widget.translations,
    child: Directionality(
      textDirection: widget.translations.isRightToLeft
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Builder(
        builder: (context) =>
            widget.builder(context, widget.translations.strings),
      ),
    ),
  );
}

/// A localized native text view with explicit language direction and alignment.
class TransLocaleText<T extends Object> extends StatelessWidget {
  const TransLocaleText(
    this.message, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  final String Function(T strings) message;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final t = TransLocaleScope.of<T>(context);
    return Text(
      message(t.strings),
      style: style,
      textDirection: t.isRightToLeft ? TextDirection.rtl : TextDirection.ltr,
      textAlign:
          textAlign ?? (t.isRightToLeft ? TextAlign.right : TextAlign.left),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
