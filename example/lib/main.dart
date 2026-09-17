import 'package:dartnative/dartnative.dart';
import 'package:translocale_dartnative/translocale_dartnative.dart';
import 'dartnative_plugin_registrant.dart';
import 'translocale_bundle.g.dart';

void main() {
  DartNativePluginRegistrant.registerAll();
  runApp(const TranslationExample());
}

class TranslationExample extends StatefulWidget {
  const TranslationExample({super.key});
  @override
  State<TranslationExample> createState() => _TranslationExampleState();
}

class _TranslationExampleState extends State<TranslationExample> {
  late final translations = TransLocale(
    catalog: translocaleCatalog,
    locale: const String.fromEnvironment('APP_LOCALE', defaultValue: 'en'),
    delivery: const bool.fromEnvironment('DELIVERY_ENABLED')
        ? DartNativeDelivery(
            projectId: const String.fromEnvironment('DELIVERY_PROJECT'),
            schemaHash: const String.fromEnvironment('DELIVERY_SCHEMA'),
            token: const String.fromEnvironment('DELIVERY_TOKEN'),
            channel: const String.fromEnvironment(
              'DELIVERY_CHANNEL',
              defaultValue: 'preview',
            ),
            apiBaseUrl: const String.fromEnvironment(
              'DELIVERY_ORIGIN',
              defaultValue: 'https://translocale.io',
            ),
          )
        : null,
  );

  @override
  Widget build(BuildContext context) => App(
    title: 'TransLocale',
    home: TransLocaleBuilder(
      translations: translations,
      builder: (context, t) => Scaffold(
        appBar: AppBar(title: const Text('TransLocale')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransLocaleText(
                  'symbol',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TransLocaleText(
                  'hello',
                  arguments: {'name': 'Sam'},
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 12),
                TransLocaleText(
                  'items',
                  arguments: {'count': 3},
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 32),
                for (final language in const {
                  'en': 'English',
                  'fr': 'Français',
                  'ar': 'العربية',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Button(
                      variant: ButtonVariant.filled,
                      onPressed: () => t.setLocale(language.key),
                      child: Text(language.value),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Locale: ${t.locale} · Source: ${t.state.source}'),
                if (t.delivery != null) ...[
                  Text(
                    'Delivery: ${t.state.status}${t.state.error == null ? '' : ' (${t.state.error})'}',
                  ),
                  const SizedBox(height: 12),
                  Button(
                    variant: ButtonVariant.bordered,
                    onPressed: () {
                      t.check();
                    },
                    child: const Text('Refresh translations'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
