class DriverSettingDefinition {
  const DriverSettingDefinition({
    required this.section,
    required this.key,
    required this.defaultValue,
    required this.description,
    this.choices = const [],
  });

  final String section;
  final String key;
  final String defaultValue;
  final String description;
  final List<String> choices;
}

const driverSettingDefinitions = <DriverSettingDefinition>[
  DriverSettingDefinition(
    section: 'General',
    key: 'Enabled',
    defaultValue: '1',
    description:
        "1 = frame generation on (our bundled, Ampere-optimized DLSS-G runtime). 0 = off: the game's own DLSS-G loads\n"
        'unchanged, which means no frame generation on Ampere. The proxy still forwards the real system DLL either way.',
    choices: ['1', '0'],
  ),
  DriverSettingDefinition(
    section: 'FrameGeneration',
    key: 'Optimized',
    defaultValue: '1',
    description:
        "1 = optimized kernels (recommended; the validated fastest set, output bit-identical to stock).\n"
        "0 = stock kernels: the runtime's original numerics, no optimization. Both modes run on Ampere.",
    choices: ['1', '0'],
  ),
  DriverSettingDefinition(
    section: 'FrameGeneration',
    key: 'MaxGeneratedFrames',
    defaultValue: '3',
    description:
        'Frame-generation multiplier ceiling: 3 = up to 4X (factory default), 5 = up to 6X on the 310.9 build only.\n'
        'The game requests its own count within this; a game with dynamic MFG otherwise runs at the maximum by default, which\n'
        'users found too high (issues #497/#499). A game whose own Streamline plugin is 4X stays at 4X either way.\n'
        'Clamped to what the bundled runtime supports: 6X on the 310.9 build, 4X on the 310.1 build.',
    choices: ['3', '5'],
  ),
  DriverSettingDefinition(
    section: 'Compatibility',
    key: 'Preset',
    defaultValue: 'Auto',
    description:
        'DLSS-G render preset (UI recomposition), 310.9 build only. Auto = let the game / driver profile decide (default).\n'
        'A = force UI recomposition off. B = force it on (cleaner HUD/UI inside generated frames), but B only takes effect\n'
        'when the game hands DLSS-G both a HUD-less image and a UI plane; most games do not, and then B is a no-op. 310.1 ignores this.',
    choices: ['Auto', 'A', 'B'],
  ),
  DriverSettingDefinition(
    section: 'Logging',
    key: 'Level',
    defaultValue: '1',
    description: '0 = off, 1 = errors, 2 = configuration and capability, 3 = kernel and evaluation traces. Written to Directory.',
    choices: ['0', '1', '2', '3'],
  ),
  DriverSettingDefinition(
    section: 'Logging',
    key: 'Directory',
    defaultValue: r'dlssg_sm86\logs',
    description: 'Written to Directory.',
  ),
  DriverSettingDefinition(
    section: 'Runtime',
    key: 'Mode',
    defaultValue: 'Bundled',
    description: 'Bundled = always use the embedded, matched runtime and backend (normal use; no game DLL version matching).',
    choices: ['Bundled'],
  ),
  DriverSettingDefinition(
    section: 'Runtime',
    key: 'CacheDirectory',
    defaultValue: '',
    description: r"Empty uses %LOCALAPPDATA%\DlssgSm86\bundles. A relative path is based on this INI's folder.",
  ),
];

final _driverSettingDefinitionsByKey = {
  for (final definition in driverSettingDefinitions)
    _definitionKey(definition.section, definition.key): definition,
};

DriverSettingDefinition? driverSettingDefinition(String section, String key) =>
    _driverSettingDefinitionsByKey[_definitionKey(section, key)];

String _definitionKey(String section, String key) =>
    '${section.toLowerCase()}/$key'.toLowerCase();
