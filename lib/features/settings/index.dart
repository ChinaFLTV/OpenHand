// settings is a widget-bundle feature (no Controller — uses global SettingsController in lib/app/state/).
// barrel only exposes entry widgets + top-level dialog helpers.
export 'widgets/settings_view.dart'
    show SettingsView, showAiModelEditorDialog;
export 'widgets/thread_session_management_dialog.dart'
    show ThreadSessionManagementDialog;
